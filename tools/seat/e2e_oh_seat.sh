#!/bin/bash
# e2e_oh_seat.sh — split-key end-to-end test of the oh-seat CLI.
#
#   OPENHUMAN_CALLER_KEY_FILE=... OPENHUMAN_SEAT_KEY_FILE=... OH_SEAT=path/to/oh-seat \
#     tools/seat/e2e_oh_seat.sh [URL]
#
# A plain curl caller (caller-scope key) sends a chat request declaring one
# tool; oh-seat (responder-scope key) answers it with a tool call, the caller
# returns the tool output, and oh-seat replies. Also checks that two
# consumers with their own state files both see the same message.
set -eu
URL=${1:-https://api.juwanh.com}
OHS=${OH_SEAT:-oh-seat}
CK=$(grep -o 'ohk_[A-Za-z0-9_]*' "$OPENHUMAN_CALLER_KEY_FILE" | head -1)
T=$(mktemp -d); trap 'rm -rf $T' EXIT
export OH_SEAT_URL=$URL OH_SEAT_KEY_FILE=$OPENHUMAN_SEAT_KEY_FILE
A="$OHS --state $T/a.json"; B="$OHS --state $T/b.json"
pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; exit 1; }

$A status >/dev/null && $B status >/dev/null || fail "seat key cannot read the inbox"
TAG=e2e-$RANDOM
TOOLS='[{"type":"function","function":{"name":"shell","description":"run a command","parameters":{"type":"object","properties":{"cmd":{"type":"string"}},"required":["cmd"]}}}]'
REQ1=$(jq -nc --arg t "say hi ($TAG)" --argjson tools "$TOOLS" \
  '{model:"openhuman-human",messages:[{role:"system",content:"e2e"},{role:"user",content:$t}],tools:$tools}')
curl -s -A oh-seat-e2e -H "Authorization: Bearer $CK" -H 'Content-Type: application/json' \
  "$URL/v1/chat/completions" -d "$REQ1" > $T/r1.json &
CURL=$!

$A next --timeout 60 > $T/a.out || fail "consumer A got nothing"
grep -q "$TAG" $T/a.out && pass "consumer A sees the message" || fail "A: $(cat $T/a.out)"
grep -q "tools in .*shell" $T/a.out && pass "first sight lists the conversation's tools" || fail "no tools line"
$B next --timeout 30 > $T/b.out && grep -q "$TAG" $T/b.out && pass "consumer B sees it too (own cursor)" || fail "B: $(cat $T/b.out)"

$A tool shell cmd='echo hi' --timeout 1 > $T/tool.out || true
INV=$(grep -o 'call_[A-Za-z0-9]*' $T/tool.out | head -1)
[ -n "$INV" ] && pass "tool call issued ($INV), result pending" || fail "tool: $(cat $T/tool.out)"
wait $CURL
jq -e '.choices[0].message.tool_calls[0].function.name=="shell"' $T/r1.json >/dev/null && pass "caller received tool_calls" || fail "caller: $(head -c 300 $T/r1.json)"

CALLID=$(jq -r '.choices[0].message.tool_calls[0].id' $T/r1.json)
REQ2=$(jq -c --arg id "$CALLID" '.choices[0].message as $m | input | .messages += [$m, {role:"tool",tool_call_id:$id,content:"hi"}]' $T/r1.json <(echo "$REQ1"))
curl -s -A oh-seat-e2e -H "Authorization: Bearer $CK" -H 'Content-Type: application/json' \
  "$URL/v1/chat/completions" -d "$REQ2" > $T/r2.json &
CURL=$!
$A result "$INV" --timeout 60 > $T/res.out && grep -q '^hi' $T/res.out && pass "oh-seat result got the output" || fail "result: $(cat $T/res.out)"
$A reply "final answer $TAG" > /dev/null || fail "reply"
wait $CURL
jq -e --arg t "final answer $TAG" '.choices[0].message.content==$t' $T/r2.json >/dev/null && pass "caller received the reply" || fail "caller: $(head -c 300 $T/r2.json)"
echo "ALL PASS"
