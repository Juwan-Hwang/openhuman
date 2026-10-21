#!/usr/bin/env python3
"""Local scripted seat for e2e-testing terminal clients against a local OpenHuman.

Usage: seatbot.py BASE_URL KEY LOGFILE [SECONDS]
For each new chat conversation: ask for a shell tool call (echo), wait for the
result, then reply with reasoning + text that quotes the result. Aux requests
get a short title. Later chat turns get an echo reply.
"""
import json, sys, time, urllib.request

BASE, KEY, LOG = sys.argv[1], sys.argv[2], sys.argv[3]
DEADLINE = time.time() + float(sys.argv[4] if len(sys.argv) > 4 else 600)
SHELL_NAMES = ["Bash", "bash", "shell", "exec_command", "local_shell", "RunCommand", "run_command", "terminal"]


def call(method, path, body=None, timeout=100):
    req = urllib.request.Request(BASE + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return {"http_error": e.code, "body": e.read().decode(errors="replace")[:500]}


def log(what, **kw):
    with open(LOG, "a") as f:
        f.write(json.dumps({"t": time.strftime("%H:%M:%S"), "what": what, **kw}, ensure_ascii=False) + "\n")


def shell_input(tool, cmd):
    params = tool.get("input_schema") or tool.get("parameters") or {}
    props = params.get("properties", {})
    req = params.get("required", [])
    inp = {}
    if "command" in props:
        inp["command"] = ["bash", "-lc", cmd] if props["command"].get("type") == "array" else cmd
    elif "cmd" in props:
        inp["cmd"] = cmd
    else:
        inp[(req or ["command"])[0]] = cmd
    for k in req:
        if k not in inp:
            inp[k] = "seat e2e test" if props.get(k, {}).get("type", "string") == "string" else False
    return inp


seen_conv = set()
cursor = 0
while time.time() < DEADLINE:
    r = call("GET", f"/v1/seat/inbox?after={cursor}&wait=20", timeout=40)
    if "cursor" not in r:
        log("inbox_error", r=r); time.sleep(2); continue
    cursor = r["cursor"]
    for ev in r.get("events", []):
        t = ev.get("type")
        log("event", type=t, conv=ev.get("conversation_id"), kind=ev.get("kind"), client=ev.get("client"),
            text=(ev.get("text") or ev.get("output") or "")[:300], tool_id=ev.get("tool_id"))
        if t != "message.received":
            continue
        conv = ev["conversation_id"]
        if ev.get("kind") == "auxiliary":
            log("reply", r=call("POST", "/v1/seat/reply", {"conversation_id": conv, "text": "Seat test"}))
            continue
        if conv in seen_conv:
            log("reply", r=call("POST", "/v1/seat/reply", {"conversation_id": conv, "text": "收到：" + (ev.get("text") or "")[:80]}))
            continue
        seen_conv.add(conv)
        caps = call("GET", f"/v1/seat/capabilities?conversation_id={conv}&view=full")
        tools = caps.get("tools") or []
        names = [t.get("id") for t in tools]
        log("caps", conv=conv, client=caps.get("client"), tools=names, sp_len=caps.get("system_prompt_len"))
        tool = next((t for n in SHELL_NAMES for t in tools if t.get("id") == n), None)
        if tool is None:
            log("reply", r=call("POST", "/v1/seat/reply", {"conversation_id": conv, "text": "没有可用的 shell 工具。", "reasoning": "no shell tool"}))
            continue
        inp = shell_input(tool, "echo seat-e2e-ok")
        tc = call("POST", "/v1/seat/tool-call", {"conversation_id": conv, "tool": tool["id"], "input": inp,
                                                 "text": "先跑个命令。", "reasoning": "测试：先验证工具往返。", "wait": 90}, timeout=110)
        log("tool_call", tool=tool["id"], input=inp, r=tc)
        out = ((tc.get("result") or {}).get("output") or "")
        rep = call("POST", "/v1/seat/reply", {"conversation_id": conv, "reasoning": "结果回来了，总结一下。",
                                             "text": "工具结果：" + out.strip()[:200]})
        log("reply", r=rep)
