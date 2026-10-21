#!/bin/bash
# waitany.sh CURSOR MAXSECS -> returns on first message.received or tool.result after CURSOR
K=$(cat ${OPENHUMAN_SEAT_KEY_FILE:-$HOME/.openhuman/seat_key}); C=$1; END=$(( $(date +%s) + ${2:-1100} ))
while [ $(date +%s) -lt $END ]; do
  R=$(curl -s -m 100 "${OPENHUMAN_URL:-https://api.juwanh.com}/v1/seat/inbox?after=$C&wait=85&types=message.received,tool.result" -H "Authorization: Bearer $K")
  N=$(echo "$R" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d["events"]))' 2>/dev/null)
  if [ "${N:-0}" -gt 0 ]; then echo "$R" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps({"cursor":d["cursor"],"waiting_turns":d["waiting_turns"],"events":[{k:(v[:1500] if isinstance(v,str) else v) for k,v in e.items() if k!="system_prompt_head"} for e in d["events"]]},ensure_ascii=False))'; exit 0; fi
done; echo '{"timeout":true}'
