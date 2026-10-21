# Agent Seat tools

- `seat.sh listen|reply|tool|caps`, `seattool.sh`, `waitany.sh`: shell helpers for an agent sitting in the responder seat (`/v1/seat/*`). Key read from `$OPENHUMAN_SEAT_KEY_FILE` (default `~/.openhuman/seat_key`), server from `$OPENHUMAN_URL`.
- `seatbot.py`: scripted seat for end-to-end tests (asks the caller for one shell tool call, then replies with reasoning + text).
- `run_e2e.sh <claude|codex|opencode|pi>`: starts a local memory-backend server + seatbot and drives one terminal client against it (Claude Code via `/v1/messages`, Codex via `/v1/responses`, opencode and pi via `/v1/chat/completions`).

## oh-seat (recommended)

`oh-seat` is a single static Rust binary (source `cli/`) for agents that only have a terminal. Design and full reference: `docs/seat-cli.md`. End-to-end test: `e2e_oh_seat.sh`.

```
export OH_SEAT_KEY_FILE=~/.openhuman/seat_key   # responder key
oh-seat next                                    # wait for the next message (≤100 s)
oh-seat tool bash command='uname -a'           # caller runs it; prints the result
oh-seat reply "Done." --reasoning "checked uname"
```

Verified against production 2026-10-21 with pi as the caller (message → caps → tool round-trip → reply delivered live).
