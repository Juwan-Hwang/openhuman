#!/usr/bin/env python3
"""Live end-to-end probe for the three interop fixes.

   1. A human `tool.invoke` must reach the agent as a real `tool_calls`
      array with `finish_reason: tool_calls` — not as a JSON string with
      `finish_reason: stop`.
   2. Async mode must return `202` + `invocation_id`, and the reply must be
      retrievable from `GET /v1/replies/<id>`.
   3. Two different conversation ids must map to two different conversations
      instead of one shared transcript.

This drives the **real** paths: the human replies over the WebSocket gateway
with an actual `tool.invoke` event, not via the `/v1/mock/*` endpoints. That
distinction matters — the mock endpoints bypass `parse_reply()` and are
exactly what hid the tool-call downgrade in the first place.

Usage:
    python e2e_async_toolcall_isolation.py                     # your-server
    python e2e_async_toolcall_isolation.py http://127.0.0.1:8080 ws://127.0.0.1:8080

Requires: websockets, requests
"""

from __future__ import annotations

import asyncio
import json
import sys
import time
import uuid

import requests
import websockets


def http() -> requests.Session:
    """A session that ignores proxy env vars.

    A local HTTP proxy will happily pass short requests and then cut a
    long-poll connection loose mid-flight, which looks exactly like a server
    bug. These probes deliberately hold connections open, so talk directly.
    """
    session = requests.Session()
    session.trust_env = False
    return session


SESSION = http()

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080"
WS_BASE = sys.argv[2] if len(sys.argv) > 2 else BASE.replace("https://", "wss://").replace(
    "http://", "ws://"
)
API_KEY = "ohk_demo_alice_codex"
MODEL = "openhuman-human"

# The probe declares its tools, exactly like a real agent does. This is not
# decoration: capability registration reads `tools[]` from the request, and a
# `tool.invoke` for an undeclared tool is rejected with `tool_not_found`.
# Probing without the declaration tests a state no real client is ever in.
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "probe_ping",
            "description": "Health probe used by the OpenHuman end-to-end test.",
            "parameters": {
                "type": "object",
                "properties": {"note": {"type": "string"}},
            },
        },
    }
]

PASS, FAIL = "PASS", "FAIL"
results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, ok, detail))
    print(f"  [{PASS if ok else FAIL}] {name}" + (f" — {detail}" if detail else ""))


def auth() -> dict:
    return {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}


async def ws_wait_for(ws, *event_types, conversation: str | None = None,
                      timeout: float = 15.0):
    """Read WS frames until one of `event_types` arrives.

    `conversation` matters: the server drains pending offline messages the
    moment a device connects, so a fresh socket can immediately be handed a
    message left over from an earlier run. Matching on conversation id keeps
    the probe from acting on a stale turn.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        raw = await asyncio.wait_for(ws.recv(), timeout=max(0.1, deadline - time.time()))
        try:
            ev = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if ev.get("event_type") not in event_types:
            continue
        if conversation is not None and ev.get("conversation_id") != conversation:
            continue
        return ev
    raise TimeoutError(f"no {event_types} (conversation={conversation}) within {timeout}s")


async def main() -> int:
    session = f"probe-{uuid.uuid4().hex[:8]}"

    # ── 0. Liveness ────────────────────────────────────────────────
    print("\n[0] Health endpoints")
    for path in ("/health", "/healthz"):
        try:
            r = SESSION.get(f"{BASE}{path}", timeout=10)
            check(f"GET {path}", r.status_code == 200, f"HTTP {r.status_code}")
        except Exception as exc:  # noqa: BLE001
            check(f"GET {path}", False, str(exc))

    # ── 1. Auth still works after the key-hash migration ───────────
    print("\n[1] Authentication (SHA-256 key lookup)")
    r = SESSION.get(f"{BASE}/v1/models", headers=auth(), timeout=10)
    check("GET /v1/models with demo key", r.status_code == 200, f"HTTP {r.status_code}")
    r = SESSION.get(f"{BASE}/v1/models", headers={"Authorization": "Bearer ohk_bogus"}, timeout=10)
    check("bogus key rejected", r.status_code == 401, f"HTTP {r.status_code}")

    # ── 2. Async mode + real WS `tool.invoke` ──────────────────────
    print("\n[2] Async mode + tool.invoke -> tool_calls")
    ws = await websockets.connect(f"{WS_BASE}/ws?api_key={API_KEY}", open_timeout=15)
    await ws_wait_for(ws, "session.connected")

    try:
        conv_a = f"{session}-a"
        resp = SESSION.post(
            f"{BASE}/v1/chat/completions",
            headers={**auth(), "X-OpenHuman-Mode": "async",
                     "X-OpenHuman-Conversation-Id": conv_a},
            json={"model": MODEL, "tools": TOOLS,
                  "messages": [{"role": "user", "content": "run a probe"}]},
            timeout=15,
        )
        check("async request returns 202", resp.status_code == 202, f"HTTP {resp.status_code}")
        body = resp.json()
        inv_id = body.get("id", "")
        poll_url = body.get("poll_url", "")
        conversation = body.get("conversation_id", "")
        check("202 carries invocation_id", inv_id.startswith("inv_"), inv_id or "(none)")

        # Match on the conversation id from the 202 body: a freshly connected
        # device is immediately drained of pending offline messages, which can
        # include turns left over from an earlier run.
        msg = await ws_wait_for(ws, "message.received", conversation=conversation)
        check("human received the message",
              msg.get("data", {}).get("text") == "run a probe",
              msg.get("data", {}).get("text", "")[:40])

        # Reply with a REAL tool.invoke — the path that used to be silently
        # downgraded to text.
        tool_invocation = f"inv_{uuid.uuid4().hex[:12]}"
        await ws.send(json.dumps({
            "event_type": "tool.invoke",
            "conversation_id": conversation,
            "invocation_id": tool_invocation,
            "tool_id": "probe_ping",
            "input": {"note": "async tool call"},
        }))

        r = SESSION.get(f"{BASE}{poll_url}?wait=15", headers=auth(), timeout=30)
        check("poll returns 200", r.status_code == 200, f"HTTP {r.status_code}")
        done = r.json()
        check("invocation completed", done.get("status") == "completed",
              str(done.get("status")))

        message = (done.get("choices") or [{}])[0].get("message", {})
        finish = (done.get("choices") or [{}])[0].get("finish_reason")

        # THE regression guard:
        check("reply is a tool_calls array", isinstance(message.get("tool_calls"), list),
              json.dumps(message)[:120])
        check("finish_reason == tool_calls", finish == "tool_calls", str(finish))
        calls = message.get("tool_calls") or []
        if calls:
            check("function name preserved", calls[0].get("function", {}).get("name") == "probe_ping",
                  str(calls[0].get("function", {}).get("name")))
            check("call id round-trips the invocation_id",
                  calls[0].get("id") == tool_invocation,
                  f"{calls[0].get('id')} vs {tool_invocation}")
            try:
                args = json.loads(calls[0]["function"].get("arguments", "{}"))
                check("arguments parsed", args.get("note") == "async tool call", json.dumps(args))
            except Exception as exc:  # noqa: BLE001
                check("arguments parsed", False, str(exc))
    finally:
        await ws.close()

    # ── 3. Conversation isolation ──────────────────────────────────
    print("\n[3] Conversation isolation")
    def ask(conversation: str) -> str:
        r = SESSION.post(
            f"{BASE}/v1/chat/completions",
            headers={**auth(), "X-OpenHuman-Mode": "async",
                     "X-OpenHuman-Conversation-Id": conversation},
            json={"model": MODEL, "tools": TOOLS,
                  "messages": [{"role": "user", "content": "hello"}]},
            timeout=15,
        )
        return (r.json() or {}).get("conversation_id", "")

    # UUIDv7 ids share a time-ordered prefix, so compare the tail — printing
    # only the head makes two distinct ids look identical.
    def tail(cid: str) -> str:
        return cid[-8:] if cid else "(none)"

    a1 = ask(f"{session}-x")
    b = ask(f"{session}-y")
    a2 = ask(f"{session}-x")
    check("different chat windows -> different conversations",
          bool(a1) and a1 != b, f"...{tail(a1)} vs ...{tail(b)}")
    check("same chat window -> same conversation", bool(a1) and a1 == a2, f"...{tail(a1)}")

    # ── 4. Unknown invocation ──────────────────────────────────────
    print("\n[4] Error handling")
    r = SESSION.get(f"{BASE}/v1/replies/inv_nope", headers=auth(), timeout=10)
    check("unknown invocation -> 404", r.status_code == 404, f"HTTP {r.status_code}")

    failed = [n for n, ok, _ in results if not ok]
    print("\n" + "=" * 60)
    print(f"{len(results) - len(failed)}/{len(results)} checks passed")
    if failed:
        print("FAILED: " + ", ".join(failed))
    print("=" * 60)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
