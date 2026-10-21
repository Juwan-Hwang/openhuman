#!/bin/bash
# run_e2e.sh CLIENT "prompt"  — fresh local server + seatbot, then run one CLI
set -u
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
C=$1; P=${2:-"运行一个 shell 命令 echo 测试，然后告诉我结果"}
D=/workspace/work/e2e/$C; rm -rf $D; mkdir -p $D/work; cd $D
BIN=/workspace/work/target/debug/openhuman-server
KEY=ohk_demo_alice_codex; URL=http://127.0.0.1:18080
pkill -f "openhuman-server" 2>/dev/null; pkill -f seatbot.py 2>/dev/null; sleep 1
OPENHUMAN_PORT=18080 OPENHUMAN_HOST=127.0.0.1 OPENHUMAN_SEAT_TTL_SECS=900 RUST_LOG=info,openhuman_server=debug \
  timeout 400 $BIN > server.log 2>&1 &
SPID=$!
for i in $(seq 1 30); do curl -s -m 1 $URL/health >/dev/null && break; sleep 0.5; done
timeout 380 python3 /workspace/work/e2e/seatbot.py $URL $KEY seat.log 370 > seatbot.out 2>&1 &
BPID=$!
sleep 1
export PATH=/workspace/tools/npm/node_modules/.bin:$PATH HOME=$D/home; mkdir -p $HOME
cd $D/work
case $C in
  claude)
    ANTHROPIC_BASE_URL=$URL ANTHROPIC_API_KEY=$KEY ANTHROPIC_MODEL=openhuman-human ANTHROPIC_SMALL_FAST_MODEL=openhuman-human \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 \
    timeout 300 claude -p "$P" --model openhuman-human --permission-mode bypassPermissions --output-format json > ../cli.out 2> ../cli.err ;;
  codex)
    OH_KEY=$KEY timeout 300 codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox \
      -c model_provider=oh -c 'model_providers.oh={name="oh",base_url="http://127.0.0.1:18080/v1",env_key="OH_KEY",wire_api="responses"}' \
      -m openhuman-human "$P" > ../cli.out 2> ../cli.err ;;
  opencode)
    cat > opencode.json <<EOF
{"\$schema":"https://opencode.ai/config.json","provider":{"oh":{"npm":"@ai-sdk/openai-compatible","name":"OpenHuman","options":{"baseURL":"$URL/v1","apiKey":"$KEY"},"models":{"openhuman-human":{"name":"openhuman-human","tool_call":true}}}},"model":"oh/openhuman-human","permission":{"bash":"allow","edit":"allow"}}
EOF
    timeout 300 opencode run -m oh/openhuman-human "$P" > ../cli.out 2> ../cli.err ;;
  pi)
    mkdir -p $HOME/.pi/agent
    cat > $HOME/.pi/agent/models.json <<EOF
{"providers":{"oh":{"baseUrl":"$URL/v1","api":"openai-completions","apiKey":"$KEY","models":[{"id":"openhuman-human","name":"OpenHuman","reasoning":false,"input":["text","image"],"contextWindow":1000000,"maxTokens":131072}]}}}
EOF
    timeout 300 pi --provider oh --model openhuman-human -p "$P" > ../cli.out 2> ../cli.err ;;
esac
echo "cli exit=$?" > ../exit.txt
sleep 2; kill $BPID $SPID 2>/dev/null
cd $D; echo "== exit"; cat exit.txt; echo "== cli.out"; head -c 3000 cli.out; echo; echo "== cli.err"; tail -c 1500 cli.err; echo; echo "== seat.log"; cut -c1-400 seat.log
