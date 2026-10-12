#!/usr/bin/env python3

"""Live checks for cross-client isolation, turn merging, and image input.



   1. Two different clients (distinct User-Agent, no other identifying

      header) must land in different conversations — otherwise they share

      one outbound queue and one steals the other's tool calls.

   2. Prose typed before a tool tap must arrive in the same response as the

      tool call, not a later one.

   3. An `image_url` content part must reach the human, not be dropped.



Usage:

    python e2e_session_and_vision.py

    python e2e_session_and_vision.py http://127.0.0.1:8080 ws://127.0.0.1:8080/ws

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





class Client:

    """One agent identity, with its own User-Agent."""



    def __init__(self, slug: str) -> None:

        self.s = requests.Session()

        self.s.trust_env = False

        self.slug = slug

        self.s.headers.update({"User-Agent": f"openhuman-probe-{slug}/1.0"})



    def submit(self, messages: list, async_mode: bool = False, conversation: str | None = None):

        headers = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

        if conversation:

            headers["X-OpenHuman-Conversation-Id"] = conversation

        if async_mode:

            headers["X-OpenHuman-Mode"] = "async"

        return self.s.post(

            f"{BASE}/v1/chat/completions",

            headers=headers,

            json={"model": MODEL, "tools": TOOLS, "messages": messages},

            timeout=30,

        )



    def poll(self, invocation_id: str, wait: int = 15) -> dict:

        r = self.s.get(

            f"{BASE}/v1/replies/{invocation_id}?wait={wait}",

            headers={"Authorization": f"Bearer {API_KEY}"},

            timeout=wait + 25,

        )

        try:

            return r.json()

        except Exception:  # noqa: BLE001

            return {"status": f"http-{r.status_code}"}





async def find_event(events: asyncio.Queue, *types, conversation=None, timeout=25.0):

    deadline = time.time() + timeout

    held: list = []

    while time.time() < deadline:

        try:

            ev = await asyncio.wait_for(events.get(), timeout=max(0.1, deadline - time.time()))

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





# ── 1. Cross-client isolation ───────────────────────────────────────────

def check_client_isolation() -> None:

    print("\n[1] Different clients do not share a conversation")

    a = Client(f"a-{uuid.uuid4().hex[:6]}")

    b = Client(f"b-{uuid.uuid4().hex[:6]}")



    # Neither sends any identifying header — only the User-Agent differs.

    ra = a.submit([{"role": "user", "content": "hello from A"}], async_mode=True)

    rb = b.submit([{"role": "user", "content": "hello from B"}], async_mode=True)



    check("both accepted", ra.status_code == 202 and rb.status_code == 202,

          f"{ra.status_code}/{rb.status_code}")

    ca = ra.json().get("conversation_id", "")

    cb = rb.json().get("conversation_id", "")

    check("distinct conversations", bool(ca) and bool(cb) and ca != cb,

          f"{ca[:14]} vs {cb[:14]}")



    # Same client again: must resume its own thread.

    ra2 = a.submit([{"role": "user", "content": "hello again from A"}], async_mode=True)

    check("same client resumes its own conversation",

          ra2.json().get("conversation_id") == ca,

          f"{ra2.json().get('conversation_id', '')[:14]}")





# ── 2. Prose + tool in one response ─────────────────────────────────────

async def check_turn_merge(ws, events: asyncio.Queue, sess: str) -> None:

    print("\n[2] Prose and a tool call land in one response")

    api = Client(f"m-{uuid.uuid4().hex[:6]}")



    r = api.submit([{"role": "user", "content": "run a probe"}],

                   async_mode=True, conversation=f"{sess}-merge")

    if r.status_code != 202:

        check("turn submitted", False, f"HTTP {r.status_code}")

        return

    body = r.json()

    conv, inv = body.get("conversation_id"), body.get("id")

    await find_event(events, "message.received", conversation=conv)



    # Type first, then tap the tool — no explicit end-of-turn in between.

    await ws.send(json.dumps({

        "event_type": "reply.send",

        "conversation_id": conv,

        "text": "我先看个时间",

    }))

    await asyncio.sleep(0.4)

    await ws.send(json.dumps({

        "event_type": "tool.invoke",

        "conversation_id": conv,

        "invocation_id": f"inv_{uuid.uuid4().hex[:12]}",

        "tool_id": "probe_ping",

        "input": {"note": "merged"},

    }))



    done = api.poll(inv)

    check("completed", done.get("status") == "completed", str(done.get("status")))

    message = (done.get("choices") or [{}])[0].get("message", {})

    calls = message.get("tool_calls") or []

    check("tool_calls present", len(calls) == 1, f"{len(calls)} call(s)")

    check("prose present in the same message",

          message.get("content") == "我先看个时间", repr(message.get("content"))[:60])

    check("finish_reason tool_calls",

          (done.get("choices") or [{}])[0].get("finish_reason") == "tool_calls", "")





# ── 3. Image input reaches the human ────────────────────────────────────

async def check_image(ws, events: asyncio.Queue, sess: str) -> None:

    print("\n[3] Image input reaches the human")

    api = Client(f"i-{uuid.uuid4().hex[:6]}")

    # A 1x1 PNG, so the payload stays small.

    png = ("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"

           "AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")



    r = api.submit([{

        "role": "user",

        "content": [

            {"type": "text", "text": "这张图里有什么？"},

            {"type": "image_url", "image_url": {"url": png}},

        ],

    }], async_mode=True, conversation=f"{sess}-img")



    if r.status_code != 202:

        check("image turn accepted", False, f"HTTP {r.status_code}")

        return

    conv = r.json().get("conversation_id")



    ev = await find_event(events, "message.received", conversation=conv, timeout=25)

    check("human received the message", ev is not None, "")

    if not ev:

        return

    data = ev.get("data", {})

    images = data.get("images") or []

    check("image forwarded to the human", len(images) == 1, f"{len(images)} image(s)")

    if images:

        check("image payload intact", images[0] == png, images[0][:40])

    check("text survived alongside the image",

          "这张图里有什么" in (data.get("text") or ""), repr(data.get("text"))[:60])





# ── 4. Several actions inside one turn ──────────────────────────────────

async def _open_turn(api, ws, events, sess, marker, suffix):

    r = api.submit([{"role": "user", "content": "go"}], async_mode=True,

                   conversation=f"{sess}-{marker}-{suffix}")

    if r.status_code != 202:

        return None, None

    body = r.json()

    conv, inv = body.get("conversation_id"), body.get("id")

    deadline = time.time() + 15

    while time.time() < deadline:

        await asyncio.sleep(0.3)

        if any(getattr(e, "get", lambda _k: None)("event_type") == "message.received"

               and e.get("conversation_id") == conv for e in _peek_all(events)):

            break

        try:

            await asyncio.wait_for(ws.ping(), timeout=2)

        except Exception:  # noqa: BLE001

            break

    return conv, inv





async def _gap(ws, seconds: float):

    """Wait `seconds`, keeping the socket warm.

    Sleeps in short slices rather than one 1s chunk: a single sleep would
    overshoot to the next whole second, and at the 2000ms merge window
    that overshoot is the difference between "the tap joins this turn"
    and "it misses the window entirely". The gap has to mean what it says.
    """

    end = time.time() + seconds

    while True:

        remaining = end - time.time()

        if remaining <= 0:

            return

        await asyncio.sleep(min(remaining, 0.25))

        try:

            await asyncio.wait_for(ws.ping(), timeout=2)

        except Exception:  # noqa: BLE001

            return





def _send(ws, payload: dict):

    return ws.send(json.dumps(payload))





async def check_prose_then_later_tool(ws, events: asyncio.Queue, sess: str) -> None:

    """Prose, then a tool tap a beat later, still inside the merge window.

    The turn is held open for `OPENHUMAN_MERGE_WINDOW_MS` (2000ms by
    default) after the first action so a second one can join it. This gap
    is deliberately well inside that window -- it is the pause a human
    actually takes before reaching for a tool, not a slow round trip.

    Beyond the window the tap no longer joins this response: it is parked
    and delivered on the next request instead (see `check_parked_reply`
    in e2e_live_fixes.py). That is the intended trade-off -- widening the
    window would delay *every* turn by that much.
    """

    api = Client(f"t-{uuid.uuid4().hex[:6]}")

    marker = f"a-{uuid.uuid4().hex[:6]}"

    print("\n[4] Prose and a later tool tap share one message")



    conv, inv = await _open_turn(api, ws, events, sess, marker, "t")

    if not conv:

        check("turn submitted", False, "")

        return

    await _send(ws, {"event_type": "reply.send",

                     "conversation_id": conv, "text": "我先说一句"})

    await _gap(ws, 1.2)

    await _send(ws, {"event_type": "tool.invoke", "conversation_id": conv,

                     "invocation_id": f"inv_{uuid.uuid4().hex[:12]}",

                     "tool_id": "probe_ping", "input": {"note": "late"}})

    await _gap(ws, 2.5)



    out = api.poll(inv)

    msg = (out.get("choices") or [{}])[0].get("message", {})

    calls = msg.get("tool_calls") or []

    check("prose and later tool call in one message",

          msg.get("content") == "我先说一句" and len(calls) == 1,

          f"content={msg.get('content')!r} calls={len(calls)}")





async def check_two_tools_one_array(ws, events: asyncio.Queue, sess: str) -> None:

    """Two tools tapped back to back arrive as one tool_calls array."""

    api = Client(f"t-{uuid.uuid4().hex[:6]}")

    marker = f"b-{uuid.uuid4().hex[:6]}"

    print("\n[5] Back-to-back tools become one array")



    conv, inv = await _open_turn(api, ws, events, sess, marker, "t")

    if not conv:

        check("turn submitted", False, "")

        return

    for note in ("one", "two"):

        await _send(ws, {"event_type": "tool.invoke", "conversation_id": conv,

                         "invocation_id": f"inv_{uuid.uuid4().hex[:12]}",

                         "tool_id": "probe_ping", "input": {"note": note}})

        await _gap(ws, 0.5)

    await _gap(ws, 2.5)



    out = api.poll(inv)

    msg = (out.get("choices") or [{}])[0].get("message", {})

    calls = msg.get("tool_calls") or []

    check("two tools arrive as one tool_calls array", len(calls) == 2,

          f"{len(calls)} call(s)")





async def check_messages_until_closed(ws, events: asyncio.Queue, sess: str) -> None:

    """Several messages stay in the turn until the human closes it."""

    api = Client(f"t-{uuid.uuid4().hex[:6]}")

    marker = f"c-{uuid.uuid4().hex[:6]}"

    print("\n[6] Messages accumulate until the turn is closed")



    conv, inv = await _open_turn(api, ws, events, sess, marker, "t")

    if not conv:

        check("turn submitted", False, "")

        return

    for text in ("第一句", "第二句"):

        await _send(ws, {"event_type": "reply.send",

                         "conversation_id": conv, "text": text})

        await _gap(ws, 0.5)

    await _send(ws, {"event_type": "end.turn", "conversation_id": conv})

    await _gap(ws, 1.0)



    out = api.poll(inv)

    ch = (out.get("choices") or [{}])[0]

    content = (ch.get("message") or {}).get("content") or ""

    check("both messages stay in the turn",

          "第一句" in content and "第二句" in content, repr(content)[:60])

    check("closing the turn ends it", ch.get("finish_reason") == "stop", "")





def _peek_all(events: asyncio.Queue) -> list:

    """Snapshot the queue without draining it."""

    return list(getattr(events, "_queue", []))





async def open_console():

    """Connect to the human console, returning (ws, events, pump_task)."""

    ws = await websockets.connect(

        f"{WS_URL}?api_key={API_KEY}",

        open_timeout=20,

        # The server has no permessage-deflate support; a client that

        # negotiates it drops the moment the socket opens.

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

    await find_event(events, "session.connected")

    return ws, events, pump_task





async def main() -> int:

    sess = f"sv-{uuid.uuid4().hex[:8]}"

    check_client_isolation()



    # A fresh console per check: the upstream reclaims idle sockets after

    # roughly 40s, and one long-lived connection cannot carry all of them.

    for run in (check_turn_merge, check_image, check_prose_then_later_tool,
                check_two_tools_one_array, check_messages_until_closed):
        # The Cloudflare leg intermittently drops freshly opened sockets
        # (no close frame -- the TCP connection just vanishes seconds in),
        # even with zero business traffic. A check killed by a transport
        # error is retried once on a new connection before counting as
        # failed; a check failing its assertions is not retried.
        last_exc = None
        for attempt in (1, 2):
            ws, events, pump_task = await open_console()
            try:
                await run(ws, events, sess)
                last_exc = None
                break
            except Exception as exc:  # noqa: BLE001
                last_exc = exc
                if attempt == 1:
                    print(f"  [RETRY] {run.__name__} died ({type(exc).__name__}), retrying...")
            finally:
                pump_task.cancel()
                try:
                    await ws.close()
                except Exception:  # noqa: BLE001
                    pass
            await asyncio.sleep(2)
        if last_exc is not None:
            # The upstream reclaims idle sockets after roughly 40s; a check
            # that outlives its connection reports as failed rather than
            # aborting the whole run.
            check(f"{run.__name__.removeprefix('check_')} ran to completion",
                  False, type(last_exc).__name__)



    failed = [n for n, ok, _ in results if not ok]

    print("\n" + "=" * 62)

    print(f"{len(results) - len(failed)}/{len(results)} checks passed")

    if failed:

        print("FAILED: " + ", ".join(failed))

    print("=" * 62)

    return 1 if failed else 0





if __name__ == "__main__":

    sys.exit(asyncio.run(main()))

