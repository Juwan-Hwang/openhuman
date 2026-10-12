#!/usr/bin/env python
"""Find the payload-size threshold at which inbound messages stop reaching the human."""

import asyncio
import json
import threading
import time

import requests
import websockets

KEY = "ohk_demo_alice_codex"
WS_URL = "ws://127.0.0.1:8080/ws"
ASK = "请把本周的进度表发给我"



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

async def connect():
    for _ in range(6):
        try:
            url = f"{WS_URL}?api_key={KEY}"
            ws = await websockets.connect(url, **ws_ssl_kwargs(url), open_timeout=30)
            await asyncio.wait_for(ws.recv(), timeout=25)
            return ws
        except Exception:  # noqa: BLE001
            await asyncio.sleep(4)
    return None


def probe(kb, filler="x"):
    """Send one message of ~kb KB; return (delivered, http)."""
    noise = filler * (kb * 1024)
    body = {
        "model": "openhuman-human",
        "stream": True,
        "messages": [
            {
                "role": "user",
                "content": f"<system-reminder>{noise}</system-reminder>"
                f"<user_query>{ASK}</user_query>",
            }
        ],
    }
    state = {"http": "?"}

    def agent():
        try:
            r = requests.post(
                "http://127.0.0.1:8080/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {KEY}",
                    "Content-Type": "application/json",
                },
                json=body,
                stream=True,
                timeout=60,
            )
            state["http"] = r.status_code
        except Exception as exc:  # noqa: BLE001
            state["http"] = f"ERR {type(exc).__name__}"

    async def human():
        ws = await connect()
        if not ws:
            return False, state["http"]
        async with ws:
            end = time.time() + 40
            while time.time() < end:
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=35)
                except Exception:  # noqa: BLE001
                    return False, state["http"]
                e = json.loads(raw)
                if e.get("event_type") != "message.received":
                    continue
                if ASK in str(e.get("data", {}).get("text", "")):
                    return True, state["http"]

    threading.Thread(target=agent, daemon=True).start()
    return asyncio.run(human())


if __name__ == "__main__":
    print("size  delivered  http")
    for kb in [1, 3, 6, 10, 16, 32, 64, 128]:
        ok, http = probe(kb)
        print(f"{kb:>4}KB  {'YES' if ok else 'NO ':8} {http}")
        if not ok:
            print(f"   -> threshold hit at ~{kb}KB")
            break
        time.sleep(4)
