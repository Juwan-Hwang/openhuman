#!/bin/bash
# seattool.sh CONV TOOL JSON [TEXT] -> waits up to 100s for result
K=$(cat ${OPENHUMAN_SEAT_KEY_FILE:-$HOME/.openhuman/seat_key})
python3 -c 'import json,sys;print(json.dumps({"conversation_id":sys.argv[1],"tool":sys.argv[2],"input":json.loads(sys.argv[3]),"text":(sys.argv[4] if len(sys.argv)>4 else None),"wait":100}))' "$@" | curl -s -m 115 ${OPENHUMAN_URL:-https://api.juwanh.com}/v1/seat/tool-call -H "Authorization: Bearer $K" -H "Content-Type: application/json" -d @- | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d.get("result") or {};print(d.get("ok"),r.get("status"),r.get("error"));print((r.get("output") or json.dumps(d,ensure_ascii=False))[:20000])'
