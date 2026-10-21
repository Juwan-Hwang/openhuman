#!/bin/bash
# usage: seat.sh listen [after] [max_secs] | seat.sh reply CONV TEXT | seat.sh tool CONV TOOL JSON [TEXT] | seat.sh caps
B=${OPENHUMAN_URL:-https://api.juwanh.com}; K=$(cat ${OPENHUMAN_SEAT_KEY_FILE:-$HOME/.openhuman/seat_key}); H="Authorization: Bearer $K"
case "$1" in
  listen) after=${2:-0}; end=$(( $(date +%s) + ${3:-1100} ))
    while [ $(date +%s) -lt $end ]; do
      r=$(curl -s -m 95 "$B/v1/seat/inbox?after=$after&wait=85" -H "$H")
      n=$(echo "$r" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len([e for e in d["events"] if e["type"] in("message.received",)]))' 2>/dev/null)
      if [ "${n:-0}" -gt 0 ]; then echo "$r"; exit 0; fi
      c=$(echo "$r" | python3 -c 'import sys,json;print(json.load(sys.stdin)["cursor"])' 2>/dev/null); [ -n "$c" ] && after=$c
    done; echo "{\"timeout\":true,\"cursor\":$after}";;
  reply) python3 -c 'import json,sys;print(json.dumps({"conversation_id":sys.argv[1],"text":sys.argv[2]}))' "$2" "$3" | curl -s -m 20 $B/v1/seat/reply -H "$H" -H "Content-Type: application/json" -d @-;;
  tool) python3 -c 'import json,sys;print(json.dumps({"conversation_id":sys.argv[1],"tool":sys.argv[2],"input":json.loads(sys.argv[3]),"text":(sys.argv[4] if len(sys.argv)>4 else None),"wait":0}))' "$2" "$3" "$4" "$5" | curl -s -m 20 $B/v1/seat/tool-call -H "$H" -H "Content-Type: application/json" -d @-;;
  caps) curl -s -m 20 "$B/v1/seat/capabilities" -H "$H";;
esac
