#!/usr/bin/env python3
"""Human Online Keeper — keeps a WebSocket connection alive.

Usage: python human_online.py

This will print all WS events (message.received, capability.updated, etc.)
Press Ctrl+C to disconnect.
"""

import asyncio
import sys
import json
import subprocess
import io

# Fix Windows console encoding
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

def ensure_websockets():
    try:
        import websockets
        return
    except ImportError:
        print("Installing websockets...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "websockets", "-q"])
        print("Installed.")

async def main():
    import websockets

    uri = "ws://127.0.0.1:8080/ws?api_key=ohk_demo_alice_codex"
    print(f"Connecting to {uri} ...")
    try:
        async with websockets.connect(uri) as ws:
            print("Connected! Human is now ONLINE.")
            print("Waiting for agent messages...")
            print("=" * 60)
            async for msg in ws:
                try:
                    data = json.loads(msg)
                    event_type = data.get("event_type", "unknown")
                    print(f"\n[{event_type}]")
                    # Truncate long text to avoid console issues
                    safe = json.dumps(data, indent=2, ensure_ascii=True)
                    if len(safe) > 2000:
                        safe = safe[:2000] + "...(truncated)"
                    print(safe)
                    print("-" * 60)
                except Exception as e:
                    print(f"\n[parse error: {e}] {msg[:200]}")
                    print("-" * 60)
    except Exception as e:
        print(f"Connection error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    ensure_websockets()
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nDisconnected.")
