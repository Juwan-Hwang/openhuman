# oh-seat — the Agent Seat CLI

`oh-seat` lets an AI agent sit in the OpenHuman **responder** seat from any
terminal: callers (Claude Code, Codex, opencode, pi, any OpenAI-compatible
client) send messages, and the agent answers them and runs tools on the
caller's machine. People use the Flutter app; this CLI is designed for AI
agents only, and every choice below favours an agent driving a shell one
command at a time.

It is a single static Rust binary (like `gh` and `codex`): no runtime, no
dependencies, starts instantly. Source: `cli/`. Build: `cargo build --release`
in `cli/`; release workflow ready at `deploy/ci/oh-seat-release.yml` (copy into `.github/workflows/` to enable; pushing workflows needs a token with `workflow` scope)
on tags `oh-seat-v*`.

## Setup

```
export OH_SEAT_URL=https://api.juwanh.com          # default
export OH_SEAT_KEY_FILE=~/.openhuman/seat_key      # default; a responder-scope ohk_ key
```

`OH_SEAT_KEY` works too but puts the key in shell history. State (cursor,
active conversation, buffered events) lives in `~/.openhuman/seat-state.json`
(`--state` / `OH_SEAT_STATE`). Each state file is its own consumer with its
own server-side cursor, so several agents can read the same seat.

## The loop

```
oh-seat next                          # block until a caller message; prints it, makes it active
oh-seat tool Bash command='ls -la'    # caller runs it; prints the output
oh-seat reply 'Done.' --next          # answer, then wait for the next message
```

| command | what it does |
|---|---|
| `next [--timeout S] [--all]` | Wait for a message (default 100 s, exit 2 if none). First sight of a conversation also prints its tool names. |
| `reply TEXT \| -f FILE \| -` | Reply in the active (or `-c`) conversation. `--more` keeps the turn open, `-r` adds reasoning, `--next` waits for the next message. |
| `tool NAME key=value…` | Ask the caller to run a tool, wait for its result. Input: `key=value` (value parsed as JSON if valid), `key:=value` (force string), `key=@file`, `key=@-` (stdin), one JSON object, or `-` (whole input from stdin). |
| `result ID` | Keep waiting for a tool result that outlived `tool --timeout`. |
| `caps [--tool NAME [--schema]] [--full] [--diff]` | Tools as signatures (`Bash(command*: string, timeout: number)`), one tool's parameters, the whole system prompt, or what changed. |
| `history`, `convs`, `use CONV`, `save`, `status` | Context, conversation list, switch active, persist, health. |

`--json` on any command prints one JSON object per line.

## Design rules (why it looks like this)

- **One command = one complete step.** `tool` sends and waits; `reply --next`
  answers and waits. Fewer round-trips through the agent's context.
- **Every wait is bounded** by `--timeout` (default 100 s, below common shell
  tool limits). Nothing is lost on timeout: events are buffered in the state
  file with the cursor, and `result ID` / `next` pick them up.
- **No quoting traps.** Text and tool inputs can come from files or stdin
  (`-f -`, `key=@-`), so multi-line commands and quotes never go through the
  shell twice.
- **Auxiliary calls are labelled.** Title/suggestion requests print
  `AUX: answer with …; reply with -c CONV` and never take over the active
  conversation, so a later bare `reply` lands in the real chat. The format
  comes from the server's `expected_format`, with a local fallback.
- **Long tool output is capped** (`OH_SEAT_MAX_OUTPUT`, default 30000 chars):
  head and tail are shown, the whole output is saved to
  `~/.openhuman/results/<id>.txt` for grep.
- **Exit codes mean something:** 0 ok, 2 nothing new before the timeout,
  3 network/auth/server (message says which, e.g. key lacks responder scope),
  4 usage.
- **Tool result by id** needs no server endpoint: the per-consumer cursor plus
  the persisted buffer already guarantee a result is never dropped.

## Tests

- Unit: `cargo test` in `cli/`.
- End to end with split keys (caller-scope key for a curl caller, responder
  key for oh-seat, two consumers): `tools/seat/e2e_oh_seat.sh`.
- Verified live 2026-10-21 against Claude Code, Codex and opencode callers.
