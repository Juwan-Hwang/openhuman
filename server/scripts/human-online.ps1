# Human Online Keeper — keeps a WebSocket connection alive
# so OpenHuman treats the human as "online" and pushes messages
# to this connection instead of marking them as Pending.
#
# Usage: powershell -ExecutionPolicy Bypass -File human-online.ps1
#
# This will print all WS events (message.received, capability.updated, etc.)
# Press Ctrl+C to disconnect.

param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$ApiKey = "ohk_demo_alice_codex"
)

$WsUrl = $BaseUrl.Replace("http://", "ws://").Replace("https://", "wss://") + "/ws?api_key=$ApiKey"

Write-Host "Connecting to $WsUrl ..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to disconnect." -ForegroundColor Yellow
Write-Host ""

# Use Python for WebSocket since PowerShell doesn't have native WS support
$pythonScript = @"
import asyncio
import sys
import json

try:
    import websockets
except ImportError:
    print("Installing websockets...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "websockets", "-q"])
    import websockets

async def main():
    uri = "$WsUrl"
    print(f"Connecting to {uri} ...")
    try:
        async with websockets.connect(uri) as ws:
            print("Connected! Human is now ONLINE.")
            print("=" * 60)
            async for msg in ws:
                try:
                    data = json.loads(msg)
                    event_type = data.get("event_type", "unknown")
                    print(f"[{event_type}] {json.dumps(data, indent=2, ensure_ascii=False)}")
                    print("-" * 60)
                except:
                    print(f"[raw] {msg}")
                    print("-" * 60)
    except Exception as e:
        print(f"Connection error: {e}")

asyncio.run(main())
"@

$pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonPath) {
    $pythonPath = (Get-Command python3 -ErrorAction SilentlyContinue).Source
}
if (-not $pythonPath) {
    Write-Host "Python not found. Please install Python first." -ForegroundColor Red
    exit 1
}

& $pythonPath -c $pythonScript
