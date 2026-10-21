# Agent Seat tools

- `seat.sh listen|reply|tool|caps`, `seattool.sh`, `waitany.sh`: shell helpers for an agent sitting in the responder seat (`/v1/seat/*`). Key read from `$OPENHUMAN_SEAT_KEY_FILE` (default `~/.openhuman/seat_key`), server from `$OPENHUMAN_URL`.
- `seatbot.py`: scripted seat for end-to-end tests (asks the caller for one shell tool call, then replies with reasoning + text).
- `run_e2e.sh <claude|codex|opencode|pi>`: starts a local memory-backend server + seatbot and drives one terminal client against it (Claude Code via `/v1/messages`, Codex via `/v1/responses`, opencode and pi via `/v1/chat/completions`).
