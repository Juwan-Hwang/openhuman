# `oh-seat` — the Agent Seat CLI (design)

Goal: the most comfortable way for an **AI agent with only a terminal** to sit in the OpenHuman responder seat. No MCP required (many agents cannot load MCP; every agent can run a command).

## Why a CLI, and what makes it comfortable for an AI

An agent drives a terminal one command at a time and reads the output back into its context. So the tool must:

1. **One command = one complete step.** "Wait for the next thing that needs me", "reply", "run this tool and give me the result". Never make the agent loop, sleep, or track cursors.
2. **Short, structured output.** Default output is compact, readable text with the fields the agent acts on (conversation, client, the message, tool results). `--json` gives one JSON object per line for agents that prefer parsing.
3. **State lives in the tool, not in the agent's head.** Cursor, the active conversation, the last capabilities snapshot are kept in a small state file (`~/.openhuman/seat-state.json`, override `OH_SEAT_STATE`).
4. **Blocking with a hard ceiling the agent chooses.** Agents' shells kill commands after a timeout (often 2–10 min). Every blocking command takes `--timeout SECONDS` and returns cleanly (exit code 2, "nothing yet") instead of being killed mid-ack.
5. **Never lose an event.** The cursor is advanced only after the events have been printed.
6. **Zero dependencies, cross-platform.** Single-file Python 3.8+ using only the standard library; runs on Linux, macOS and Windows (Git Bash / PowerShell). Always sends a User-Agent (Cloudflare rejects requests without one).
7. **Exit codes mean something.** 0 = done, 2 = timed out with nothing new, 3 = HTTP/auth error, 4 = usage error.

## Configuration

| Env | Meaning |
|---|---|
| `OH_SEAT_URL` | server base URL (default `https://api.juwanh.com`) |
| `OH_SEAT_KEY` | responder key, or `OH_SEAT_KEY_FILE` pointing at a file holding it |
| `OH_SEAT_STATE` | state file path |
| `OH_SEAT_CONSUMER` | consumer name (for the per-consumer cursor, phase 2) |

## Commands

```
oh-seat next [--timeout 600] [--all]        block until something needs a response; print it
oh-seat reply TEXT [-c CONV] [--reasoning R] [--more]
oh-seat tool NAME [JSON_INPUT] [-c CONV] [--text T] [--timeout 1800]
                                            ask the caller to run a tool; block until the result
oh-seat caps [-c CONV] [--full] [--diff]    tools + system prompt of the conversation (diff vs last view)
oh-seat history [-c CONV] [--limit 20]
oh-seat convs                               conversations this seat has seen (from state)
oh-seat use CONV                            set the active conversation
oh-seat save [-c CONV]                      persist the conversation on the server
oh-seat status                              url, cursor, active conversation, waiting turns
```

- `-c` defaults to the active conversation, which `next` sets to the conversation of the newest message.
- `next` returns on `message.received` (and `conversation.started` printed as a header). Tool results are consumed by `tool` itself; `--all` shows every event type.
- `next` marks auxiliary requests (title generation, suggestions, skill review) with `AUX` and, where it can tell, the expected answer format, so the agent replies in the right shape without reading the whole system prompt.
- `reply` closes the turn by default; `--more` keeps it open for another reply.
- `tool` has no 100 s ceiling: it posts the call, then follows the inbox until the matching `tool.result` arrives (approval prompts can take minutes). Other events seen meanwhile are kept in the state file and returned by the next `next`, never dropped.
- `caps --diff` shows only what changed since the last `caps` for that conversation (system prompts are often 10–20k characters).

## Typical agent loop

```
oh-seat next --timeout 540          # → conv, client, the user's message
oh-seat tool Bash '{"command":"ls"}'   # → the output
oh-seat reply "Here is what I found ..."
oh-seat next --timeout 540
```

## Phases

1. **CLI (this branch):** commands above, client-side cursor/state, buffered events, aux tagging from the message text.
2. **Server:** per-consumer cursor on `/v1/seat/inbox?consumer=` so two pollers never ack each other's events; aux events carry `kind:"auxiliary"` and `expected_format`; `tool.result` lookup by `invocation_id` (`GET /v1/seat/tool-result/:id`) so `tool` can resume after a restart.
3. **Tests:** split caller / responder keys; `seatbot.py` rewritten on top of `oh-seat`; prod e2e with Claude Code, Codex, opencode, pi.
