# Internal Model: Capability

Capability describes **what a participant can do** — not what they are allowed to do.

---

## 1. Design Principle

OpenHuman is **not a tool approval framework**.

```
❌  Agent → "Can I use terminal?" → Human approves → Agent runs terminal
✅  Human → "I can review_design" → Agent discovers → Agent decides to ask
```

Agent tools (terminal, filesystem, browser, github) belong to the agent's own
environment. OpenHuman has no visibility or control over them.

Capabilities are **descriptive metadata** that help participants understand each
other's value. They drive UI presentation (e.g., showing capability badges on
a human's profile) and enable smart routing (e.g., an agent searching for a
human who can `review_design`).

---

## 2. Human Capability Descriptor

```json
{
  "id": "review_design",
  "participant_type": "human",
  "display_name": "Design Review",
  "description": "Can review UI/UX designs and provide structured feedback.",
  "input_schema": {
    "type": "object",
    "properties": {
      "design_url": { "type": "string", "format": "uri" },
      "context": { "type": "string" }
    },
    "required": ["design_url"]
  },
  "output_schema": {
    "type": "object",
    "properties": {
      "rating": { "type": "integer", "minimum": 1, "maximum": 5 },
      "notes": { "type": "array", "items": { "type": "string" } }
    }
  },
  "metadata": {
    "category": "design",
    "avg_response_minutes": 15
  }
}
```

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` (kebab-case) | ✅ | Unique capability identifier (e.g., `review_design`) |
| `participant_type` | `enum` | ✅ | `human` · `agent` — who provides this capability |
| `display_name` | `string` | ✅ | Human-readable label |
| `description` | `string` | ❌ | What this capability entails |
| `input_schema` | `object (JSON Schema)` | ❌ | Expected input format (for structured requests) |
| `output_schema` | `object (JSON Schema)` | ❌ | Expected output format (for structured responses) |
| `metadata` | `object` | ❌ | Free-form bag (category, response time, etc.) |

---

## 3. Agent Capability Descriptor (Phase 7)

Agents declare their own capabilities — the **tools they expose** to the human.
This is an **observation and interaction layer**: the human sees what the agent
can do and can request a tool invocation. OpenHuman **does not execute** the
tool — it only transports the request and visualizes the result.

```json
{
  "id": "github_create_issue",
  "name": "Create GitHub Issue",
  "description": "Creates an issue in a GitHub repository.",
  "category": "github",
  "input_schema": {
    "type": "object",
    "properties": {
      "repo": { "type": "string" },
      "title": { "type": "string" },
      "body": { "type": "string" }
    },
    "required": ["repo", "title"]
  },
  "output_schema": {
    "type": "object",
    "properties": {
      "issue_number": { "type": "integer" },
      "html_url": { "type": "string", "format": "uri" }
    }
  },
  "ui_schema": {
    "component": "form",
    "fields": [
      { "name": "repo", "widget": "select", "options": ["openhuman/openhuman"] },
      { "name": "title", "widget": "text" },
      { "name": "body", "widget": "textarea" }
    ]
  },
  "permissions": ["repo:issues:write"],
  "metadata": {
    "icon": "github",
    "owner": "octobot"
  }
}
```

### AgentCapability Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | `string` (kebab-case) | ✅ | Unique capability/tool identifier |
| `name` | `string` | ✅ | Human-readable display name |
| `description` | `string` | ❌ | What this tool does |
| `category` | `string` | ❌ | Grouping label (e.g., `github`, `terminal`, `browser`) |
| `input_schema` | `object (JSON Schema)` | ❌ | Expected input parameters |
| `output_schema` | `object (JSON Schema)` | ❌ | Expected output shape |
| `ui_schema` | `object` | ❌ | UI rendering hints for the human client |
| `permissions` | `string[]` | ❌ | Required permission scopes |
| `metadata` | `object` | ❌ | Free-form bag |

### OpenAI tools/functions Compatibility

AgentCapability is **structurally compatible** with OpenAI's `tools` / `functions`
format. The `id` maps to `function.name`, `description` maps directly, and
`input_schema` maps to `function.parameters`. This allows agents that already
declare OpenAI tools to publish them to OpenHuman without transformation.

---

## 4. Agent Context (Phase 7)

AgentContext provides **non-sensitive runtime metadata** about an agent's
environment. This helps the human understand the agent's working context —
without exposing secrets, API tokens, or internal state.

```json
{
  "agent_id": "agt_demo_codex",
  "system_prompt": "You are a coding assistant...",
  "model": {
    "name": "gpt-4o",
    "provider": "openai",
    "max_tokens": 4096
  },
  "runtime": {
    "platform": "linux",
    "version": "0.1.0",
    "session_id": "sess_abc123"
  },
  "environment": {
    "repo": "openhuman/openhuman",
    "branch": "main",
    "working_directory": "/workspace"
  }
}
```

### AgentContext Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `agent_id` | `string` | ✅ | The agent this context belongs to |
| `system_prompt` | `string` | ❌ | The system prompt in use (may be truncated) |
| `model` | `object` | ❌ | Model metadata: `{ name, provider, max_tokens }` |
| `runtime` | `object` | ❌ | Runtime info: `{ platform, version, session_id }` |
| `environment` | `object` | ❌ | Environment info: `{ repo, branch, working_directory }` |

> **Security**: AgentContext must **never** contain API keys, tokens,
> passwords, or other secrets. It is intended for human-facing display.

---

## 5. Capability Registry

Capabilities are **registered**, not invented ad-hoc. The server maintains a
registry of known capability descriptors. Participants reference capabilities
by ID in their `capabilities[]` array.

```
CapabilityRegistry
├── human/answer_questions
├── human/review_design
├── human/provide_feedback
├── human/share_expertise
├── agent/coding
├── agent/analysis
└── agent/search
```

New capabilities can be registered via the internal protocol (future API).
Participants declare which registered capabilities they provide.

---

## 6. Human Capabilities

Examples from the architecture specification:

| ID | Display Name | Description |
|---|---|---|
| `answer_questions` | Answer Questions | Can answer domain-specific questions |
| `review_design` | Design Review | Can review UI/UX or system designs |
| `provide_feedback` | Provide Feedback | Can give structured feedback on work |
| `share_expertise` | Share Expertise | Can share deep knowledge in a domain |

A human's capabilities are declared in `HumanIdentity.capabilities[]`.

---

## 7. Agent Capabilities

Agents also declare capabilities — this helps humans understand what the
agent can contribute to the conversation.

| ID | Display Name | Description |
|---|---|---|
| `coding` | Coding | Can write, modify, and debug source code |
| `analysis` | Analysis | Can analyze codebases, data, or architecture |
| `search` | Search | Can search the web, documentation, or codebases |

An agent's capabilities are declared in `AgentIdentity.capabilities[]`.

---

## 8. Capability Discovery Flow (Phase 7)

### 8.1 Agent Connects and Publishes Manifest

```
1. Agent connects (POST /v1/chat/completions or future WS)
2. Agent sends `capability.manifest` event containing:
   - AgentCapability[] — tools the agent exposes
   - AgentContext — runtime context
3. Server stores capabilities + context in the database
4. Server pushes `capability.updated` event to connected human clients
5. Human client renders the capability list in the UI
```

### 8.2 Human Subscribes

```
Human WS connected
       ↓
Server sends `capability.updated` on agent manifest change
       ↓
Human UI renders: "Agent has tools: [GitHub Create Issue, Terminal Run, ...]"
```

### 8.3 Discovery via SDK API

```
1. Agent connects with API Key
2. OpenHuman resolves AgentIdentity + bound HumanIdentity
3. Agent can query: GET /v1/agents/{id}/capabilities (SDK API, not OpenAI)
4. Server returns capability descriptors
5. Agent constructs a message: "I need design review for X"
6. Human receives the message, sees agent capabilities: [coding, analysis]
7. Human responds with feedback
```

> The capability query is an **SDK-level API**, not part of the OpenAI
> compatibility surface. Agents that only speak OpenAI API will not query
> capabilities directly — they simply send messages. Capability discovery
> is primarily for **human clients** (to understand the agent) and for
> **SDK-based integrations** (to route requests intelligently).

---

## 9. Tool Invocation Model (Phase 7)

OpenHuman is a **transport and visualization layer** for tool invocation.
It does **not** execute tools. The flow is:

```
Human UI
   ↓ clicks "Create GitHub Issue"
   ↓ fills form (generated from input_schema / ui_schema)
   ↓
Server receives `tool.invoke`
   ↓
Server routes to Agent (via SSE or WS)
   ↓
Agent receives `tool.invoke` request
   ↓
Agent executes the tool in its own environment
   ↓
Agent sends `tool.result` back
   ↓
Server routes `tool.result` to Human WS
   ↓
Human UI renders the result
```

### 9.1 `tool.invoke` (Human → Server → Agent)

```json
{
  "event_type": "tool.invoke",
  "conversation_id": "cnv_xxx",
  "data": {
    "invocation_id": "inv_0189abc123",
    "tool_id": "github_create_issue",
    "input": {
      "repo": "openhuman/openhuman",
      "title": "Bug: login fails",
      "body": "Steps to reproduce..."
    }
  }
}
```

### 9.2 `tool.result` (Agent → Server → Human)

```json
{
  "event_type": "tool.result",
  "conversation_id": "cnv_xxx",
  "data": {
    "invocation_id": "inv_0189abc123",
    "tool_id": "github_create_issue",
    "status": "success",
    "output": {
      "issue_number": 42,
      "html_url": "https://github.com/openhuman/openhuman/issues/42"
    },
    "error": null
  }
}
```

> **Key Principle**: OpenHuman is the **pipe**, not the executor. The agent
> owns tool execution. The human owns the decision to invoke. OpenHuman
> owns the transport, visualization, and audit trail.

---

## 10. Relationship to OpenAI Function Calling

OpenAI's API has `tools` / `functions` for structured agent-tool interaction.

**OpenHuman does not map capabilities to OpenAI tools.**

| OpenAI `functions` | OpenHuman Capabilities |
|---|---|
| Agent calls a function; server executes; returns result | Human provides a capability; agent sends a message; human responds |
| Machine-to-machine contract | Human-in-the-loop communication |
| Synchronous, programmatic | Asynchronous, conversational |

If an agent uses OpenAI function calling, those functions are handled entirely
within the agent's environment. OpenHuman is the **human communication channel**,
not a function execution engine.

However, the `tool.invoke` / `tool.result` model in Phase 7 allows the human
to **request** that the agent invoke one of its own tools — this is the reverse
direction of OpenAI function calling, and is purely observational.

---

## 11. Capability Events

See `event.md` §2.5 — `capability.updated` is emitted when a participant's
declared capabilities change. This allows real-time UI updates (e.g., a human
adding a new skill badge to their profile triggers a refresh on all
connected clients).

Phase 7 adds:

| Event Type | Direction | Description |
|---|---|---|
| `capability.manifest` | Agent → Server | Agent publishes its full capability manifest |
| `capability.updated` | Server → Human | Server notifies human clients of capability changes |
| `tool.invoke` | Human → Server → Agent | Human requests an agent tool invocation |
| `tool.result` | Agent → Server → Human | Agent returns the result of a tool invocation |

---

## Appendix A — Implementation notes (2026-10)

Reference: `server/src/profile.rs`, `server/src/ws/handler.rs`.

- Primary discovery is HTTP `tools[]` extraction on every chat request —
  no client changes needed. WS `capability.manifest` is an optional
  native extension that supersedes it when present.
- Human `tool.invoke` is validated against stored capabilities, then
  delivered as a standard OpenAI `tool_calls` response; the agent's
  `role: "tool"` answer returns as a `tool.result` event. OpenHuman never
  executes tools.
