// Minimal Anthropic (/v1/messages) <-> OpenAI (/v1/chat/completions) translation proxy.
// Purpose: let claude-code (Anthropic-native) talk to OpenHuman (OpenAI-compatible).
const http = require('http');

// All four are overridable: the defaults match a server started with
// `cargo run` and its seeded demo key, so the bridge works out of the box
// locally. Point it at a real deployment with env vars instead of editing.
const UPSTREAM = process.env.OPENHUMAN_UPSTREAM || 'http://127.0.0.1:8080';
const UPSTREAM_MODEL = process.env.OPENHUMAN_MODEL || 'openhuman-human';
const API_KEY = process.env.OPENHUMAN_API_KEY || 'ohk_demo_alice_codex';
const LISTEN_PORT = Number(process.env.PORT || 8799);

function remapModel(m){ return UPSTREAM_MODEL; }  // always use openhuman-human

function systemToText(system){
  if(!system) return '';
  if(typeof system==='string') return system;
  if(Array.isArray(system)) return system.map(b=> b&&b.type==='text'? b.text : '').join('\n');
  return '';
}

function mapMessages(messages){
  const out=[];
  for(const m of (messages||[])){
    const role=m.role, c=m.content;
    if(role==='assistant'){
      if(typeof c==='string'){ out.push({role:'assistant', content:c}); continue; }
      let text=''; const tool_calls=[];
      for(const b of c){
        if(b.type==='text') text+=b.text;
        else if(b.type==='tool_use') tool_calls.push({id:b.id||('call_'+Math.random().toString(36).slice(2)), type:'function', function:{name:b.name, arguments:JSON.stringify(b.input||{})}});
      }
      out.push({role:'assistant', content:text||null, tool_calls: tool_calls.length?tool_calls:undefined});
    } else if(role==='user'){
      if(typeof c==='string'){ out.push({role:'user', content:c}); continue; }
      let text=''; const toolMsgs=[];
      for(const b of c){
        if(b.type==='text') text+=b.text;
        else if(b.type==='tool_result') toolMsgs.push({role:'tool', tool_call_id:b.tool_use_id, content: typeof b.content==='string'? b.content : JSON.stringify(b.content)});
      }
      if(text) out.push({role:'user', content:text});
      for(const t of toolMsgs) out.push(t);
    } else {
      out.push({role, content: typeof c==='string'?c:JSON.stringify(c)});
    }
  }
  return out;
}

function mapTools(tools){
  if(!tools) return undefined;
  return tools.map(t=>({type:'function', function:{name:t.name, description:t.description||'', parameters:t.input_schema||{type:'object',properties:{}}}}));
}

function mapToolChoice(tc){
  if(!tc) return undefined;
  if(tc==='auto'||tc.type==='auto') return 'auto';
  if(tc==='any'||tc.type==='any') return 'required';
  if(tc.type==='tool') return {type:'function', function:{name:tc.name}};
  return undefined;
}

function buildAnthropicSSE(res, model, text, toolCalls, usage){
  const events=[];
  const msgId='msg_'+Math.random().toString(36).slice(2);
  events.push({type:'message_start', data:{type:'message_start', message:{id:msgId, type:'message', role:'assistant', model, content:[], usage:{input_tokens:usage.input||0, output_tokens:usage.output||0}}}});
  let idx=0;
  if(text){
    events.push({type:'content_block_start', data:{type:'content_block_start', index:idx, content_block:{type:'text', text:''}}});
    events.push({type:'content_block_delta', data:{type:'content_block_delta', index:idx, delta:{type:'text_delta', text}}});
    events.push({type:'content_block_stop', data:{type:'content_block_stop', index:idx}});
    idx++;
  }
  for(const tc of toolCalls){
    events.push({type:'content_block_start', data:{type:'content_block_start', index:idx, content_block:{type:'tool_use', id:tc.id, name:tc.name, input:{}}}});
    events.push({type:'content_block_delta', data:{type:'content_block_delta', index:idx, delta:{type:'input_json_delta', partial_json:tc.arguments}}});
    events.push({type:'content_block_stop', data:{type:'content_block_stop', index:idx}});
    idx++;
  }
  const stop_reason = toolCalls.length ? 'tool_use' : 'end_turn';
  events.push({type:'message_delta', data:{type:'message_delta', delta:{stop_reason, stop_sequence:null}, usage:{output_tokens:usage.output||0}}});
  events.push({type:'message_stop', data:{type:'message_stop'}});
  for(const ev of events){
    res.write(`event: ${ev.type}\n`);
    res.write(`data: ${JSON.stringify(ev.data)}\n\n`);
  }
}

const server = http.createServer((req,res)=>{
  // GET /v1/models - proxy to upstream
  if(req.method==='GET' && req.url.startsWith('/v1/models')){
    const u=new URL(UPSTREAM+'/v1/models');
    const r=http.request({hostname:u.hostname, port:u.port, path:u.pathname, method:'GET', headers:{'Authorization':'Bearer '+API_KEY}}, resp=>{
      let d=''; resp.on('data',c=>d+=c); resp.on('end',()=>{
        res.writeHead(200,{'content-type':'application/json'});
        res.end(d);
      });
    });
    r.on('error', e=>{ res.writeHead(502); res.end(String(e)); });
    r.end();
    return;
  }

  // POST /v1/messages - translate Anthropic -> OpenAI
  if(req.method==='POST' && req.url.startsWith('/v1/messages')){
    let body=''; req.on('data',c=>body+=c); req.on('end',()=>{
      let rb; try{ rb=JSON.parse(body); }catch(e){ res.writeHead(400); res.end('bad json'); return; }
      const model=remapModel(rb.model);
      const system=systemToText(rb.system);
      const messages=mapMessages(rb.messages);
      const tools=mapTools(rb.tools);
      const tool_choice=mapToolChoice(rb.tool_choice);
      const allowedNames=new Set((rb.tools||[]).map(t=>t.name));
      const openaiReq={ model, messages, stream:true, stream_options:{include_usage:true} };
      if(system) openaiReq.messages.unshift({role:'system', content:system});
      if(tools) openaiReq.tools=tools;
      if(tool_choice) openaiReq.tool_choice=tool_choice;
      if(rb.max_tokens) openaiReq.max_tokens=rb.max_tokens;
      if(typeof rb.temperature==='number') openaiReq.temperature=rb.temperature;

      console.error('[proxy] -> openhuman model=%s tools=%d msgs=%d', model, (tools||[]).length, messages.length);
      res.writeHead(200,{'content-type':'text/event-stream','cache-control':'no-cache','connection':'keep-alive'});

      const u=new URL(UPSTREAM+'/v1/chat/completions');
      const r=http.request({hostname:u.hostname, port:u.port, path:u.pathname, method:'POST', headers:{'content-type':'application/json','accept':'text/event-stream','Authorization':'Bearer '+API_KEY}}, resp=>{
        if(resp.statusCode!==200){
          let err=''; resp.on('data',c=>err+=c); resp.on('end',()=>{
            console.error('[proxy] upstream error %s: %s', resp.statusCode, err.slice(0,300));
            buildAnthropicSSE(res, model, '[upstream error '+resp.statusCode+'] '+err.slice(0,200), [], {input:0,output:0});
            res.end();
          });
          return;
        }
        let buf='', text=''; const toolCalls=[]; const usage={input:0,output:0};
        resp.on('data', chunk=>{
          buf+=chunk.toString(); let idx;
          while((idx=buf.indexOf('\n'))>=0){
            let line=buf.slice(0,idx).trim(); buf=buf.slice(idx+1);
            if(!line.startsWith('data:')) continue;
            let data=line.slice(5).trim(); if(data==='[DONE]') continue;
            let j; try{ j=JSON.parse(data); }catch(e){ continue; }
            const d=j.choices&&j.choices[0]&&j.choices[0].delta;
            if(d){
              if(d.content) text+=d.content;
              if(d.tool_calls){
                for(const tc of d.tool_calls){
                  const i=tc.index||0;
                  if(!toolCalls[i]) toolCalls[i]={id:tc.id||('call_'+i), name:'', arguments:''};
                  if(tc.id) toolCalls[i].id=tc.id;
                  if(tc.function){
                    if(tc.function.name) toolCalls[i].name=tc.function.name;
                    if(tc.function.arguments) toolCalls[i].arguments+=tc.function.arguments;
                  }
                }
              }
            }
            if(j.usage){ usage.input=j.usage.prompt_tokens||0; usage.output=j.usage.completion_tokens||0; }
          }
        });
        resp.on('end',()=>{
          const final=toolCalls.filter(Boolean).filter(tc=>!allowedNames.size || allowedNames.has(tc.name));
          console.error('[proxy] <- textLen=%d toolCalls=%d (names: %s)', text.length, final.length, final.map(t=>t.name).join(','));
          buildAnthropicSSE(res, model, text, final, usage);
          res.end();
        });
      });
      r.on('error', e=>{
        console.error('[proxy] upstream error %s', e);
        buildAnthropicSSE(res, model, '[upstream error] '+String(e), [], {input:0,output:0});
        res.end();
      });
      r.write(JSON.stringify(openaiReq));
      r.end();
    });
    return;
  }

  // POST /v1/messages/count_tokens - stub
  if(req.method==='POST' && req.url.startsWith('/v1/messages/count_tokens')){
    res.writeHead(200, {'content-type':'application/json'});
    res.end(JSON.stringify({input_tokens: 10}));
    return;
  }

  res.writeHead(404); res.end('not found');
});

server.listen(LISTEN_PORT, '127.0.0.1', ()=>console.error('[proxy] Anthropic->OpenAI bridge listening on http://127.0.0.1:'+LISTEN_PORT+' -> '+UPSTREAM));
