#!/usr/bin/env python
"""
OpenHuman end-to-end live demo against the deployed server (default: http://127.0.0.1:8080).

Three roles are simulated in one process:

  1. External Agent  -> POST /v1/chat/completions (stream=true, OpenAI format)
  2. OpenHuman Server -> cloud (default: http://127.0.0.1:8080)
  3. Human (Alice)   -> WSS /ws  receives `message.received`, sends `reply.send`

Run:
  python server/scripts/e2e_live_demo.py
"""

import asyncio
import json
import sys
import threading
import time

import requests
import websockets

API_KEY = "ohk_demo_alice_codex"
BASE_URL = "http://127.0.0.1:8080"
WS_URL = f"ws://127.0.0.1:8080/ws?api_key={API_KEY}"

AGENT_QUESTION = "Hi Alice - quick one: should we go with REST or GraphQL for the new public API?"
HUMAN_REPLY = "Go REST for the public surface. GraphQL only if we hit real over-fetching complaints."

T0 = time.time()
received_event = None



def ws_ssl_kwargs(url: str) -> dict:
    """TLS options only when the URL actually asks for it.

    Passing `ssl=` to a plain `ws://` connection is an error, and the
    default target here is a local server. Honour `wss://` when someone
    points the probe at a deployed, TLS-terminated instance.
    """
    if not url.startswith("wss://"):
        return {}
    import ssl as _ssl
    ctx = _ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = _ssl.CERT_NONE
    return {"ssl": ctx}

def stamp():
    return f"[{time.time() - T0:6.2f}s]"


def hr(title):
    print(f"\n{'=' * 62}\n  {title}\n{'=' * 62}")


# ---------------------------------------------------------------- agent side
def agent_call():
    """External agent sends an OpenAI-compatible chat completion request."""
    hr("STEP 1  External Agent -> POST /v1/chat/completions  (stream=true)")
    print(f"{stamp()} role    : user")
    print(f"{stamp()} content : {AGENT_QUESTION}")
    print(f"{stamp()} waiting for the human to stream a reply over SSE...\n")

    chunks = []
    try:
        resp = requests.post(
            f"{BASE_URL}/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model": "openhuman-human",
                "stream": True,
                "messages": [{"role": "user", "content": AGENT_QUESTION}],
            },
            stream=True,
            timeout=90,
        )
    except Exception as exc:  # noqa: BLE001
        print(f"{stamp()} [agent] request failed: {exc}")
        return

    print(f"{stamp()} [agent] HTTP {resp.status_code} - SSE stream open")
    hr("STEP 4  Agent receives the human's reply as SSE chunks")

    reply_text = ""
    for raw in resp.iter_lines():
        if not raw:
            continue
        line = raw.decode("utf-8") if isinstance(raw, bytes) else raw
        if line.startswith("data: "):
            payload = line[6:]
            if payload.strip() == "[DONE]":
                print(f"{stamp()} data: [DONE]")
                break
            try:
                obj = json.loads(payload)
                delta = obj["choices"][0]["delta"].get("content")
                finish = obj["choices"][0].get("finish_reason")
                if delta:
                    chunks.append(delta)
                    reply_text += delta
                    print(f"{stamp()} data: {delta!r}")
                if finish:
                    print(f"{stamp()} finish_reason = {finish}")
            except (ValueError, KeyError, IndexError):
                pass

    print(f"\n{stamp()} [agent] full reply from human: {reply_text!r}")
    return reply_text


# ---------------------------------------------------------------- human side
async def human_side():
    """The human endpoint app: connect, receive, reply, end turn."""
    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE

    hr("STEP 2  Human client -> WSS /ws  (authenticate)")
    async with websockets.connect(WS_URL, **ws_ssl_kwargs(WS_URL), open_timeout=30) as ws:
        first = await asyncio.wait_for(ws.recv(), timeout=30)
        evt = json.loads(first)
        data = evt.get("data", {})
        print(f"{stamp()} <- {evt.get('event_type')}")
        print(f"{stamp()}    human_id     = {data.get('human_id')}")
        print(f"{stamp()}    display_name = {data.get('display_name')}")
        print(f"{stamp()} connection authenticated & registered")

        hr("STEP 3  Server pushes message.received -> human answers")
        conv_id = None
        deadline = time.time() + 60

        # drain events until we get the incoming question
        while time.time() < deadline:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=45)
            except asyncio.TimeoutError:
                print(f"{stamp()} [human] timed out waiting for message.received")
                return
            evt = json.loads(raw)
            etype = evt.get("event_type")
            data = evt.get("data", {})

            if etype == "capability.updated":
                print(f"{stamp()} <- capability.updated (agent_id={data.get('agent_id')})")
                continue
            if etype != "message.received":
                print(f"{stamp()} <- {etype}")
                continue

            conv_id = evt.get("conversation_id")
            text = data.get("text")

            # strict match: only answer the conversation that carries our own
            # question — earlier drained events are offline-backlog history.
            if text != AGENT_QUESTION:
                print(f"{stamp()}    (skip backlog) {text!r}")
                continue

            print(f"{stamp()} <- message.received  [matched this turn]")
            print(f"{stamp()}    conversation_id = {conv_id}")
            print(f"{stamp()}    text            = {text!r}")
            break

        if not conv_id:
            print(f"{stamp()} [human] no conversation received, aborting")
            return

        # human types a reply
        await asyncio.sleep(0.8)
        await ws.send(
            json.dumps(
                {
                    "event_type": "reply.send",
                    "conversation_id": conv_id,
                    "text": HUMAN_REPLY,
                }
            )
        )
        print(f"{stamp()} -> reply.send : {HUMAN_REPLY!r}")

        # wait for delivery ack, then close the turn
        while time.time() < deadline:
            raw = await asyncio.wait_for(ws.recv(), timeout=30)
            evt = json.loads(raw)
            print(f"{stamp()} <- {evt.get('event_type')} {evt.get('data', {})}")
            if evt.get("event_type") == "reply.delivered":
                break

        await ws.send(
            json.dumps({"event_type": "end.turn", "conversation_id": conv_id})
        )
        print(f"{stamp()} -> end.turn (turn closed, SSE finishes)")


def main():
    hr("OpenHuman E2E demo - your-server")
    print(f"{stamp()} base url : {BASE_URL}")
    print(f"{stamp()} api key  : {API_KEY}")

    health = requests.get(f"{BASE_URL}/health", timeout=15)
    print(f"{stamp()} /health : {health.status_code} {health.text.strip()}")

    models = requests.get(
        f"{BASE_URL}/v1/models",
        headers={"Authorization": f"Bearer {API_KEY}"},
        timeout=15,
    )
    print(f"{stamp()} /v1/models : {models.text.strip()}")

    agent_thread = threading.Thread(target=agent_call, daemon=True)
    agent_thread.start()

    # give the SSE request time to register before the human connects
    asyncio.run(human_side())

    agent_thread.join(timeout=30)
    hr("done")


if __name__ == "__main__":
    sys.exit(main())
