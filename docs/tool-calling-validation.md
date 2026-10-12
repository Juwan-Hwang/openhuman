# Tool Calling Validation — Manual Testing Guide

> **Phase 7.3** — OpenAI Tool Calling Validation Harness

## 测试目的

验证：任何 OpenAI-compatible Agent，只配置 Base URL + API Key，是否可以通过标准 `tool_calls` 被 OpenHuman 驱动。

**不涉及**：OpenHuman 专用 SDK、WebSocket capability protocol、Flutter UI。

---

## 架构

```
Agent (Claude Code / Trae / WorkBuddy)
    |
    | POST /v1/chat/completions  (含 tools[])
    |
    v
OpenHuman Server
    |
    | 1. 自动提取 tools[] → CapabilityRegistry
    | 2. 转发 user message → Human Console (WS)
    | 3. 等待 Human 回复
    |
    v
Human Console
    |
    | 选择工具 + 填写参数
    | → POST /v1/mock/tool-call  (测试端点)
    | 或 WS reply.send + __tool_call__ payload
    |
    v
OpenHuman Server
    |
    | 构造标准 OpenAI tool_calls response:
    | {
    |   "choices": [{
    |     "message": {
    |       "role": "assistant",
    |       "content": null,
    |       "tool_calls": [{
    |         "id": "call_xxx",
    |         "type": "function",
    |         "function": {
    |           "name": "Bash",
    |           "arguments": "{\"command\":\"echo hello\"}"
    |         }
    |       }]
    |     },
    |     "finish_reason": "tool_calls"
    |   }]
    | }
    |
    v
Agent 执行工具
    |
    | 下一个请求包含 role="tool" message:
    | {
    |   "role": "tool",
    |   "tool_call_id": "call_xxx",
    |   "content": "hello"
    | }
    |
    v
OpenHuman 记录 tool_result，继续对话
```

---

## 前置准备

### 1. 启动 OpenHuman Server

```bash
cd e:\openhuman\server
cargo run --release
```

Server 监听 `http://127.0.0.1:8080`。

### 2. 默认 API Key

```
ohk_demo_alice_codex
```

Agent ID: `agt_demo_codex`
Human ID: `hum_demo_alice`

---

## 手动测试步骤

### 通用步骤（适用于所有 Agent）

1. 配置 Agent 的 Base URL 为 `http://127.0.0.1:8080/v1`
2. 配置 API Key 为 `ohk_demo_alice_codex`
3. 在 Agent 中发送一条消息（例如 "Hello"）
4. 观察 OpenHuman 日志——应看到：
   ```
   Extracted agent profile from HTTP request agent_id=agt_demo_codex tools_count=N
   ```
5. 在另一个终端触发 tool call：

```bash
curl -X POST http://127.0.0.1:8080/v1/mock/tool-call \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "agt_demo_codex",
    "tool_name": "Bash",
    "arguments": {"command": "echo hello"}
  }'
```

6. 观察 Agent 是否执行了工具
7. 观察 Agent 是否在后续请求中发送了 `role: "tool"` 消息

### 测试 Claude Code

```bash
# Claude Code 配置
export ANTHROPIC_BASE_URL=http://127.0.0.1:8080/v1
export ANTHROPIC_API_KEY=ohk_demo_alice_codex

# 启动 Claude Code
claude
```

在 Claude Code 中输入：`Please list the current directory files`

预期：
- Claude Code 发送 `tools: [Bash, Edit, Read]`
- OpenHuman 日志显示 `tools_count=3`
- 使用 curl 触发 tool call：
  ```bash
  curl -X POST http://127.0.0.1:8080/v1/mock/tool-call \
    -H "Content-Type: application/json" \
    -d '{"agent_id":"agt_demo_codex","tool_name":"Bash","arguments":{"command":"ls -la"}}'
  ```
- Claude Code 执行 `ls -la` 并返回结果

### 测试 Trae

在 Trae 中配置 OpenAI-compatible provider：
- Base URL: `http://127.0.0.1:8080/v1`
- API Key: `ohk_demo_alice_codex`
- Model: `openhuman-human`

在 Trae 中输入任意消息，然后触发 tool call。

### 测试 WorkBuddy

在 WorkBuddy 的 `~/.workbuddy/models.json` 中配置自定义模型：
- Base URL: `http://127.0.0.1:8080/v1`
- API Key: `ohk_demo_alice_codex`
- Model: `openhuman-human`

---

## 验证结果表

| Agent | tools[] 发现 | tool_calls 接受 | 执行工具 | role=tool 返回 | 备注 |
|-------|-------------|----------------|---------|---------------|------|
| Claude Code | ✅ | ✅ | ✅ | ✅ | 2026-08-24 验证通过，3 个 tools 发现，Bash/echo hello 执行成功，tool result 1.2s |
| Trae | ✅ | ✅ | ✅ | ✅ | 2026-08-24 验证通过，26 个 tools 发现，Bash/echo hello 执行成功，tool result 仅 436ms |
| WorkBuddy | ✅ | ✅ | ✅ | ✅ | 2026-08-24 验证通过，24 个 tools 发现，Bash/echo hello 执行成功 |

> 填写说明：☐ = 未测试, ✅ = 通过, ❌ = 失败, ⚠️ = 部分通过

---

## API 端点参考

### `POST /v1/mock/tool-call`

触发一个标准 OpenAI `tool_calls` response。

**Request:**
```json
{
  "conversation_id": "cnv_xxx",
  // 或 "agent_id": "agt_demo_codex"
  "tool_name": "Bash",
  "arguments": {"command": "echo hello"}
}
```

**Response (成功):**
```json
{
  "ok": true,
  "conversation_id": "cnv_xxx",
  "tool_name": "Bash",
  "delivered": true,
  "note": "Tool call delivered to waiting handler. Agent will receive standard OpenAI tool_calls response."
}
```

### `POST /v1/mock/human-reply`

发送纯文本回复（不触发 tool call）。

### WS `tool.invoke` (协议原生方式，推荐)

人类客户端直接发 `tool.invoke` 事件作为本轮回复：

```json
{
  "event_type": "tool.invoke",
  "conversation_id": "cnv_xxx",
  "invocation_id": "inv_xxx",
  "tool_id": "Bash",
  "input": {"command": "echo hello"}
}
```

服务端映射为真正的 OpenAI tool call：

| `tool.invoke` 字段 | OpenAI 响应字段 |
|---|---|
| `tool_id` | `tool_calls[].function.name` |
| `input` | `tool_calls[].function.arguments` |
| `invocation_id` | `tool_calls[].id`（缺省时服务端生成） |

`finish_reason` = `tool_calls`，`content` = `null`。

> **2026-09 修复**：此前 `parse_reply()` 没有 `tool.invoke` 分支（虽然 `ws/handler.rs` 的注释声称 SSE handler 会识别它），
> 因此该路径被静默降级成 `content` 为 JSON 字符串、`finish_reason: stop` 的普通文本消息，
> 合规客户端读到的是字符串而不是 `tool_calls` 数组 → 工具永不执行。
> 上面验证表里的 ✅ 走的是 `/v1/mock/tool-call` 测试端点，绕过了 `parse_reply`，所以掩盖了这个缺陷。

### WS `reply.send` + `__tool_call__` payload

兼容写法：把 tool call 塞进 `reply.send` 的 `text` 里：

```json
{
  "event_type": "reply.send",
  "conversation_id": "cnv_xxx",
  "text": "{\"__tool_call__\":true,\"tool_name\":\"Bash\",\"arguments\":{\"command\":\"echo hello\"}}"
}
```

解析优先级：`end.turn` → `tool.invoke` → `__tool_call__` → 纯文本。

---

## 日志标记

OpenHuman 在日志中输出以下标记，便于调试：

- `[tool_call]` — 当 OpenHuman 生成 tool_calls response 时
- `[tool_result]` — 当 OpenHuman 收到 Agent 的 role=tool 消息时

示例日志：
```
[tool_call] generated for agent (streaming) conversation_id=cnv_xxx tool=Bash arguments={"command":"echo hello"}
[tool_result] received from agent tool_call_id=call_xxx content_len=6
```

---

## WorkBuddy 验证记录 (2026-08-24)

### 测试环境
- WorkBuddy 5.3.14 (CLI 2.115.0)
- OpenHuman Server (release build, in-memory backend)
- API Key: `ohk_demo_alice_codex`
- Human WebSocket keeper: `python scripts/human_online.py`

### 测试流程
1. WorkBuddy 配置 Base URL `http://127.0.0.1:8080/v1` + API Key
2. 发送消息 "我发了个 这次能成功吗"
3. WorkBuddy 发了 3 个并发 SSE 请求（同一 conversation_id），携带 24 个 tools
4. OpenHuman 自动提取 tools[] 并推送到 Human WebSocket
5. 通过 `POST /v1/mock/tool-call` 触发 `Bash` + `{"command":"echo hello"}`
6. OpenHuman 返回标准 OpenAI `tool_calls` SSE response
7. WorkBuddy 执行 `echo hello`，显示"运行成功"
8. WorkBuddy 发回 `role: "tool"` + `tool_call_id` 消息
9. 通过 `POST /v1/mock/human-reply` 发送文本回复结束对话
10. WorkBuddy 显示完整回复

### 验证结果
- tools[] 发现：✅ 24 个工具
- tool_calls 接受：✅ WorkBuddy 正确解析并执行
- 执行工具：✅ `echo hello` 运行成功
- role=tool 返回：✅ `tool_call_id` 关联正确

### 验证过程中修复的 Bug

1. **SSE keepalive 用 comment 行** → OpenAI SDK (stainless) 忽略 SSE comment 行 (`: keepalive`)，导致客户端认为连接空闲并断开。修复：改为发送 `data:` 行（heartbeat chunk — 空的 `chat.completion.chunk`）。

2. **Reply registry 用 HashMap 覆盖** → 同一 conversation 的并发 SSE 请求互相覆盖 reply channel，前一个 channel 被 drop 后 `rx.recv()` 返回 `None`，SSE 流直接结束。WorkBuddy 收到空回复。修复：改为 `Vec<Sender>` 追加式存储，`deliver` 只投递到最后一个 channel。

3. **缺少 `stream_options.include_usage` 支持** → WorkBuddy 发送 `stream_options: { include_usage: true }`，期望在流结束前收到 usage chunk。修复：在 `[DONE]` 前发送 `choices: [], usage: {...}` 的 usage chunk。
