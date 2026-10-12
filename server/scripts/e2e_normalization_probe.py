#!/usr/bin/env python
"""
Verify OpenHuman's core "cognitive protection" claim against the live server.

Sends a REAL captured WorkBuddy request (23k-char user turn: system-reminders,
identity files, tool schemas) and checks what the HUMAN actually receives on
the WebSocket timeline.

If normalization works, the human sees the small genuine `<user_query>` text
instead of the raw agent prompt dump.
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
OBS = "../observations/2026-08-24-151554-d4a.json"

T0 = time.time()



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
    print(f"\n{'=' * 64}\n  {title}\n{'=' * 64}")


def load_payload():
    with open(OBS, encoding="utf-8") as fh:
        obs = json.load(fh)
    obs["body"]["stream"] = True
    return obs


async def human_side(raw_chars, expect_text):
    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE

    async with websockets.connect(WS_URL, **ws_ssl_kwargs(WS_URL), open_timeout=30) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=30))
        print(f"{stamp()} WS connected -> {hello['data'].get('display_name')}")

        deadline = time.time() + 60
        seen = []
        while time.time() < deadline:
            try:
                evt = json.loads(await asyncio.wait_for(ws.recv(), timeout=50))
            except asyncio.TimeoutError:
                print(f"\n{stamp()} timed out; candidates seen:")
                for c in seen[-5:]:
                    print(f"   - {c}")
                return None, None
            data = evt.get("data", {})
            if evt.get("event_type") != "message.received":
                continue
            seen.append(repr(str(data.get("text", ""))[:120]))
            if expect_text not in str(data.get("text", "")):
                print(f"{stamp()} (skip backlog) {str(data.get('text'))[:60]!r}")
                continue

            conv = evt["conversation_id"]
            text = data.get("text", "")
            hr("RESULT - what the HUMAN receives")
            print(f"raw agent turn sent : {raw_chars:,} chars")
            print(f"human sees          : {len(text):,} chars")
            print(f"reduction           : {(1 - len(text) / raw_chars) * 100:.1f}%")
            print(f"conversation_id     : {conv}")
            print(f"\n--- human-readable text ---\n{text}\n---------------------------")
            print(f"contains '<user_query>' : {'<user_query>' in text}")
            print(f"contains 'system-reminder': {'system-reminder' in text}")
            return conv, text

    return None, None


def agent_side(payload):
    try:
        requests.post(
            f"{BASE_URL}/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json",
            },
            json=payload,
            stream=True,
            timeout=120,
        )
    except Exception as exc:  # noqa: BLE001
        print(f"{stamp()} agent stream ended: {exc}")


def main():
    obs = load_payload()
    body = obs["body"]
    last = body["messages"][-1]
    raw = last["content"]
    raw_chars = len(json.dumps(raw, ensure_ascii=False))
    expect_text = "请继续完成未完成的任务。"

    hr("INPUT - real captured agent request (WorkBuddy 5.3.14)")
    print(f"source          : {OBS}")
    print(f"messages        : {len(body['messages'])}")
    print(f"tools declared  : {len(body.get('tools') or [])}")
    print(f"whole body      : {len(json.dumps(body)):,} chars")
    print(f"last user turn  : {raw_chars:,} chars")
    print(f"true human ask  : {expect_text!r}  ({len(expect_text)} chars)")
    print("\nverdict if good : human sees ~10 chars instead of ~23,000")

    threading.Thread(target=agent_side, args=(body,), daemon=True).start()
    conv, _ = asyncio.run(human_side(raw_chars, expect_text))

    if not conv:
        print(f"\n{stamp()} FAILED: human never matched this turn")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
