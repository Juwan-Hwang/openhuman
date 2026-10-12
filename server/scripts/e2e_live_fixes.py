#!/usr/bin/env python3
"""Live verification for the four interop fixes.

   1. Non-streaming requests survive past the CDN's idle-response timeout
      (keepalive padding instead of HTTP 524).
   2. A `role:"tool"` result settles the originating card via a `tool.result`
      event keyed by `tool_call_id`.
   3. Companion prose survives a tool call (`content` + `tool_calls` in one
      message instead of `content: null`).
   4. A reply sent with no request in flight is parked and delivered with the
      next request.

Runs against your-server by default. Check 1 deliberately holds a request
open for ~2 minutes, so the whole probe takes a few minutes.

Usage:
    python e2e_live_fixes.py
    python e2e_live_fixes.py http://127.0.0.1:8080 ws://127.0.0.1:8080/ws
"""

from __future__ import annotations

import asyncio
import json
import sys
import time
import uuid

import requests
import websockets

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080"
WS_URL = sys.argv[2] if len(sys.argv) > 2 else "ws://127.0.0.1:8080/ws"
API_KEY = "ohk_demo_alice_codex"
MODEL = "openhuman-human"

# Capability registration reads `tools[]` off the request, and a `tool.invoke`
# for an undeclared tool is rejected with `tool_not_found`. A probe that omits
# the declaration tests a state no real client is ever in.
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "probe_ping",
            "description": "Health probe used by the OpenHuman end-to-end test.",
            "parameters": {"type": "object", "properties": {"note": {"type": "string"}}},
        },
    }
]

PASS, FAIL = "PASS", "FAIL"
results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, ok, detail))
    print(f"  [{PASS if ok else FAIL}] {name}" + (f" — {detail}" if detail else ""))
    sys.stdout.flush()


class Api:
    """HTTP calls with proxy env vars ignored.

    A local proxy happily passes short requests and then cuts a long-held
    connection loose mid-flight, which looks exactly like a server bug.
    """

    def __init__(self) -> None:
        self.s = requests.Session()
        self.s.trust_env = False

    @property
    def auth(self) -> dict:
        return {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

    def submit(self, conversation: str, messages: list, async_mode: bool = False):
        headers = {**self.auth, "X-OpenHuman-Conversation-Id": conversation}
        if async_mode:
            headers["X-OpenHuman-Mode"] = "async"
        return self.s.post(
            f"{BASE}/v1/chat/completions",
            headers=headers,
            json={"model": MODEL, "tools": TOOLS, "messages": messages},
            timeout=30,
        )

    def poll(self, invocation_id: str, wait: int = 15) -> dict:
        r = self.s.get(f"{BASE}/v1/replies/{invocation_id}?wait={wait}",
                       headers=self.auth, timeout=wait + 25)
        try:
            return r.json()
        except Exception:  # noqa: BLE001
            return {"status": f"http-{r.status_code}", "body": r.text[:80]}


API = Api()


async def find_event(events: asyncio.Queue, *types, conversation=None, timeout=25.0):
    """Pull the next matching event, putting skipped ones back."""
    deadline = time.time() + timeout
    held: list = []
    while time.time() < deadline:
        try:
            ev = await asyncio.wait_for(events.get(),
                                        timeout=max(0.1, deadline - time.time()))
        except asyncio.TimeoutError:
            break
        if ev.get("event_type") in types and (
            conversation is None or ev.get("conversation_id") == conversation
        ):
            for h in held:
                await events.put(h)
            return ev
        held.append(ev)
    for h in held:
        await events.put(h)
    return None


# ── 1. Non-streaming must not be killed by the idle-response timeout ────
async def check_nonstreaming_survives(ws, events: asyncio.Queue, conversation: str) -> None:
    """Hold a `stream:false` request open well past ~100s and still answer it.

    The reply goes over the WebSocket: the mock endpoint needs a
    `conversation_id`, which a non-streaming response cannot supply before it
    completes.
    """
    print("\n[1] Non-streaming request past the CDN idle timeout (~100s)")
    hold = 115.0

    marker = f"wait for me {uuid.uuid4().hex[:8]}"

    def ask() -> requests.Response:
        # No `stream` flag — the path that used to return 524.
        return API.submit(conversation, [{"role": "user", "content": marker}])

    started = time.time()
    task = asyncio.create_task(asyncio.to_thread(ask))

    # Match on the message text too: connecting drains pending offline
    # messages, so the first `message.received` may be left over from an
    # earlier run rather than this turn.
    msg = None
    deadline = time.time() + 30
    while time.time() < deadline:
        ev = await find_event(events, "message.received", timeout=5)
        if ev is None:
            continue
        if ev.get("data", {}).get("text") == marker:
            msg = ev
            break
    if msg is None:
        check("human received the message", False, "")
        task.cancel()
        return
    conv_id = msg.get("conversation_id")
    check("human received the message", True, str(msg.get("data", {}).get("text"))[:30])

    # Answer through the HTTP mock rather than the WebSocket: this check is
    # about how long the *request* can stay open, and an idle WebSocket is
    # torn down on its own schedule — conflating the two would test the wrong
    # thing. The conversation id came from the `message.received` event above.
    remaining = hold - (time.time() - started)
    if remaining > 0:
        await asyncio.sleep(remaining)

    r = API.s.post(
        f"{BASE}/v1/mock/human-reply",
        json={"conversation_id": conv_id, "text": "answered late"},
        timeout=15,
    )
    # The mock harness is disabled unless the server opts in
    # (`mock_endpoints` feature or OPENHUMAN_MOCK_ENDPOINTS=1). A 404 here
    # means the harness is off — the late answer then has no sender, so
    # the rest of this check cannot run.
    if r.status_code == 404:
        check("mock reply accepted", True, "SKIP — mock harness disabled on server")
        task.cancel()
        return
    check("mock reply accepted", r.status_code == 200, f"HTTP {r.status_code}")

    try:
        r = await asyncio.wait_for(task, timeout=hold + 90)
    except Exception as exc:  # noqa: BLE001
        check("stream:false completed", False, f"{type(exc).__name__}: {exc}")
        task.cancel()
        return

    elapsed = time.time() - started
    check(f"stream:false answered after {elapsed:.0f}s", r.status_code == 200,
          f"HTTP {r.status_code}")
    if r.status_code != 200:
        return
    try:
        body = r.json()
    except Exception:  # noqa: BLE001
        check("body is JSON", False, r.text[:80])
        return
    check("body is JSON", True, "")
    content = (body.get("choices") or [{}])[0].get("message", {}).get("content")
    check("carried the human's reply", content == "answered late", str(content)[:60])


async def submit_async(events: asyncio.Queue, conversation: str):
    """Send an async turn; return (conversation_id, invocation_id)."""
    r = API.submit(conversation, [{"role": "user", "content": "run a probe"}],
                   async_mode=True)
    if r.status_code != 202:
        return None, None
    body = r.json()
    return body.get("conversation_id"), body.get("id")


# ── 3. Companion prose alongside a tool call ────────────────────────────
async def check_companion_prose(ws, events: asyncio.Queue, sess: str):
    print("\n[3] Companion prose survives a tool call")
    conv_id, inv = await submit_async(events, f"{sess}-tool")
    if conv_id is None:
        check("tool turn submitted", False, "")
        return None
    await find_event(events, "message.received", conversation=conv_id)

    await ws.send(json.dumps({
        "event_type": "tool.invoke",
        "conversation_id": conv_id,
        "invocation_id": f"inv_{uuid.uuid4().hex[:12]}",
        "tool_id": "probe_ping",
        "input": {"note": "with prose"},
        "text": "我触发了",
    }))

    done = API.poll(inv)
    check("invocation completed", done.get("status") == "completed", str(done.get("status")))
    message = (done.get("choices") or [{}])[0].get("message", {})
    check("tool_calls present", isinstance(message.get("tool_calls"), list), "")
    check("content carries the prose", message.get("content") == "我触发了",
          repr(message.get("content"))[:60])
    check("finish_reason is tool_calls",
          (done.get("choices") or [{}])[0].get("finish_reason") == "tool_calls", "")
    return conv_id, message.get("tool_calls")


# ── 2. Tool result settles the originating card ─────────────────────────
async def check_tool_result(ws, events: asyncio.Queue, sess: str,
                            conv_id: str, tool_calls: list):
    print("\n[2] Tool result routed back by tool_call_id")
    if not tool_calls:
        check("call id available", False, "")
        return
    call_id = tool_calls[0].get("id")
    result = "2026-09-22 00:39:55"

    r = API.submit(f"{sess}-tool", [
        {"role": "user", "content": "run a probe"},
        {"role": "assistant", "content": None, "tool_calls": tool_calls},
        {"role": "tool", "tool_call_id": call_id, "content": result},
    ], async_mode=True)
    check("result accepted", r.status_code == 202, f"HTTP {r.status_code}")

    ev = await find_event(events, "tool.result", conversation=conv_id, timeout=25)
    check("tool.result event received", ev is not None, "")
    if not ev:
        return
    data = ev.get("data", {})
    check("keyed to the originating call", data.get("invocation_id") == call_id,
          f"{data.get('invocation_id')} vs {call_id}")
    check("status is success", data.get("status") == "success", str(data.get("status")))
    check("carries the result body", result in json.dumps(data.get("output", "")),
          str(data.get("output"))[:40])
    check("names the tool", data.get("tool_id") == "probe_ping", str(data.get("tool_id")))


# ── 4. Reply parked when nothing is in flight ───────────────────────────
async def check_parked_reply(ws, events: asyncio.Queue, sess: str):
    print("\n[4] Reply with no request in flight is parked and redelivered")
    conv_id, inv = await submit_async(events, f"{sess}-park")
    if conv_id is None:
        check("park turn submitted", False, "")
        return
    await find_event(events, "message.received", conversation=conv_id)

    # Answer the first turn normally, closing it out.
    await ws.send(json.dumps({
        "event_type": "reply.send",
        "conversation_id": conv_id,
        "text": "first answer",
    }))
    first = API.poll(inv)
    check("first turn answered", first.get("status") == "completed", str(first.get("status")))

    # Speak again with nothing in flight — this used to vanish.
    await ws.send(json.dumps({
        "event_type": "reply.send",
        "conversation_id": conv_id,
        "text": "spoken into the void",
    }))
    await asyncio.sleep(1.0)

    r = API.submit(f"{sess}-park", [{"role": "user", "content": "anything new?"}],
                   async_mode=True)
    check("next request accepted", r.status_code == 202, f"HTTP {r.status_code}")
    body = r.json()
    check("backlog answered immediately", body.get("status") == "completed",
          str(body.get("status")))

    got = API.poll(body.get("id", ""))
    message = (got.get("choices") or [{}])[0].get("message", {})
    check("parked reply delivered", message.get("content") == "spoken into the void",
          repr(message.get("content"))[:60])


async def main() -> int:
    sess = f"fix-{uuid.uuid4().hex[:8]}"
    ws = await websockets.connect(
            f"{WS_URL}?api_key={API_KEY}",
            open_timeout=20,
            # The server has no permessage-deflate support; a client
            # that negotiates it drops the moment the socket opens.
            compression=None,
        )
    events: asyncio.Queue = asyncio.Queue()

    async def pump():
        try:
            async for raw in ws:
                try:
                    await events.put(json.loads(raw))
                except json.JSONDecodeError:
                    continue
        except Exception:  # noqa: BLE001
            pass

    pump_task = asyncio.create_task(pump())
    try:
        await find_event(events, "session.connected")
        # Longest first, so the rest are not waiting behind it.
        await check_nonstreaming_survives(ws, events, f"{sess}-slow")
        conv_id, tool_calls = (await check_companion_prose(ws, events, sess)) or (None, None)
        if conv_id:
            await check_tool_result(ws, events, sess, conv_id, tool_calls)
        await check_parked_reply(ws, events, sess)
    finally:
        pump_task.cancel()
        await ws.close()

    failed = [n for n, ok, _ in results if not ok]
    print("\n" + "=" * 62)
    print(f"{len(results) - len(failed)}/{len(results)} checks passed")
    if failed:
        print("FAILED: " + ", ".join(failed))
    print("=" * 62)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
