# Round 3 plan (user said go 2026-10-21 09:46 CST: fix everything + adapt terminal CLIs, test, deploy)

Local test env: sandbox build (gcc installed), memory backend, CLIs in /workspace/tools/npm/node_modules/.bin
(claude 2.1.305 → needs Anthropic /v1/messages; codex 0.163 → wire_api=chat removed, needs /v1/responses;
opencode 1.19.3 + pi 0.73.1 → OpenAI chat ok).

## Core fixes (server/src/api/openai.rs, seat.rs, ws/handler.rs)
- [x] E1 heartbeat: first heartbeat immediately, default every 5s (OPENHUMAN_SSE_HEARTBEAT_SECS), SSE comment frames
- [x] E2 drop guard: when the SSE stream is dropped (client gone), unregister waiter so later replies park in outbound queue; seat reply reports live=false
- [x] F tool_call_id rewrite (Trae): unknown id → map to last unanswered call in conversation (by name+args, else newest); per-conversation dedupe of tool results (id or content hash) so retries/409s don't re-push
- [x] D order: tool.result before message.received
- [x] Trae image follow-up: user msg in tail that is only image/"[图片]" after tool msgs → attach images to tool.result
- [x] G session continuity: index of hashes of assistant replies we sent → conversation; strip <system-reminder>/<uploaded_files> etc. from anchor; don't key main chat on system prompt fingerprint
- [x] A no trailing "\n\n" on final reply; separator prepended between consecutive replies instead
- [x] B aux requests inherit client from key's last main request
- [x] C usage (+ selectable tokenizers: o200k default, cl100k, p50k, HF tokenizer.json; env OPENHUMAN_TOKENIZER, header x-openhuman-tokenizer): SERVER computes (user decision 09:52) via tokenizer (tiktoken-rs o200k_base) for prompt + completion; no seat-supplied usage
- [x] H reasoning: seat reply/tool-call optional reasoning → reasoning_content delta before content
- [x] #7 capability.updated conversation_id = real conversation; per-conversation context snapshot (system prompt, tools) → capabilities?conversation_id=
- [x] history: from caller/responder, role filled
- [x] seat attach drain: tool messages → tool.result not message.received
- [x] seat/send simplified {conversation_id,text}
- [x] stateless: message store in memory by default (OPENHUMAN_PERSIST_MESSAGES=1 to keep postgres); POST /v1/conversations/:id/save + seat save; Flutter button (untested)
- [x] Qoder skill-review isolation
## Adapters
- [x] POST /v1/messages via anyllm_translate crate (user: prefer existing libs)
- [x] POST /v1/responses (OpenAI Responses) as transformer
## Test
- [x] cargo test (prod throwaway container), local CLI e2e with me as seat, deploy (backup first)
