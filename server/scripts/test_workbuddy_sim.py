#!/usr/bin/env python3
"""Simulate WorkBuddy: send a streaming request and see how fast the connection drops."""
import asyncio
import sys
import json
import httpx

async def main():
    url = "http://127.0.0.1:8080/v1/chat/completions"
    headers = {
        "Authorization": "Bearer ohk_demo_alice_codex",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "WorkBuddy/5.3.14 WorkBuddy/5.3.14 CLI/2.115.0",
    }
    body = {
        "model": "openhuman-human",
        "messages": [{"role": "user", "content": "hello test"}],
        "stream": True,
        "stream_options": {"include_usage": True},
    }

    print(f"Sending streaming request to {url} ...")
    async with httpx.AsyncClient(timeout=httpx.Timeout(60.0)) as client:
        async with client.stream("POST", url, headers=headers, json=body) as resp:
            print(f"Status: {resp.status_code}")
            print(f"Content-Type: {resp.headers.get('content-type')}")
            print("Reading SSE stream...")
            line_count = 0
            async for line in resp.aiter_lines():
                line_count += 1
                ts = asyncio.get_event_loop().time()
                if line_count <= 10 or line.startswith("data:"):
                    print(f"  [{ts:.1f}] line {line_count}: {line[:120]}")
                if line_count > 100:
                    print("... too many lines, stopping")
                    break

asyncio.run(main())
