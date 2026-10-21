# Agent Seat 实测发现与修复计划（2026-10-21）

> 测试方式：Juwan 在本地多个 agent 客户端（调用方）里与 Hark 对话，Hark 通过 `/v1/seat/*` 坐在应答方。
> 线上：`api.juwanh.com`；源码：`server/`。原始逐条记录在 `SEAT_ISSUES.md`。
> 状态说明：**[已修]** 已部署；**[待修]** 尚未动代码（用户要求先记录、之后统一修）。

## 0. 已部署的修复（2026-10-21 02:48 CST，备份 tag 20261021-024424）

- [已修] `waiting_turns` 残留已关闭的 reply sender，导致误报并发 409（`storage/memory.rs`、`storage/postgres.rs`）。
- [已修] `/v1/seat/inbox` 的 `waiting_turns` 暴露了其他 human 的 conversation ID，属于跨租户泄露（`seat.rs`）。
- [已修] Seat 每次接入都会注入「人类专家已上线」。现在 Seat 默认关闭，可用 `OPENHUMAN_SEAT_ANNOUNCE=1` 打开；**真人 /ws 上线时保持原样**（用户明确要求）。
- 测试：cargo test 全部通过。clippy 只在生产副本的 `tests/ws_chain.rs` 报了一个旧的 `redundant_locals`，不是这次改动引入的。

## 0b. 第二轮修复（2026-10-21 08:10 CST 已部署，备份 tag 20261021-080626）

- [已修] P0-1 `developer` 角色按 system 处理。
- [已修] P0-2 只把「最后一条 assistant 之后」的消息当作新内容：tail 中的所有 user 拼接后，用 dsh 规则剥掉注入（runtime context / skill reminder），真实原话不再丢失；原样 tail 放在 `raw_tail`（Seat 的 full 视图里可见）。
- [已修] P0-3 没有显式 ID 时，会话 key 改为 `prm/cli:<指纹>:<client>:<首条 user 哈希>`，新会话会拿到新的 conversation_id；新会话创建时推送 `conversation.started`（Seat 和 /ws 都会收到）。**Flutter 端需要处理这个事件（新建会话卡片），属于客户端待办。**
- [部分] P0-4 辅助请求（无 tools、只有 1 条非 system 消息、带 max_tokens 或 response_format）会被标为 `kind: auxiliary`，归入 `aux:` 会话，不覆盖主 context，也不推 conversation.started。Qoder 的「技能复盘」带 tools，暂时识别不了，仍会落进主会话。
- [已修] P1-5 旧 tool.result 和旧 user 消息不再重复推送。
- [已修] P1-6 capability.updated 只在内容有变化时推送。
- [已修] P1-8 message.received 附带 `request`（client、kind、system_prompt_head、response_format、max_tokens、tool_count）；compact 视图对辅助请求直接给出输出格式要求。
- [已修] P1-9 应答方只有 Seat 时，不再注入「人类专家当前在线」；有真人设备时照旧。
- [已修] P1-10 新增 `GET /v1/seat/history?conversation_id=&limit=`。
- [已修] P2-12 `/v1/models` 返回 context_window/context_length、max_output_tokens/max_tokens（以及 camelCase 形式）、input_modalities 和 capabilities；数值可通过 `OPENHUMAN_MODEL_CONTEXT_WINDOW` / `OPENHUMAN_MODEL_MAX_OUTPUT` 覆盖。
- [已修] P2-13 识别 Qoder（system prompt 指纹）和 DeepSeek Harness（UA）。
- 线上 e2e 已验证（临时 caller key，测完已撤销）：developer 角色、注入剥离、conversation.started、流式不带在线提示、续轮只推 tool.result。
- 仍待修：#7 capability.updated 的 conversation_id 字段、#14 compact 视图补参数名、#15 附件接口、#17 seat/send 简化、#18 主动发消息、#19 重启后队列持久化、#20 唤醒机制；新发现：Seat 接入时，drain backlog 会把未送达的旧 tool 消息当成 message.received 推出来。

## 1. 用户已做的设计决定

| # | 决定 |
|---|---|
| D1 | 调用方 system_prompt（含客户端的个人记忆）**不脱敏**：接入了这个软件，应答方就有权看到原样。 |
| D2 | 「剥离/归一化」是为人类做的。**agent 应答方应拿原样的完整本轮上下文**；真人 /ws 继续用剥离后的干净版本。 |
| D3 | 调用方开新会话时，**agent 和真人两边都要能识别出这是新会话，并且分开显示**。 |
| D4 | 「人类专家已上线 / 当前在线」这类提示只对真人保留，agent seat 不注入。 |

## 2. 待修问题（按优先级）

### P0 — 阻塞或丢数据
1. **`role: "developer"` 被拒（422）**：DeepSeek Harness 默认发送 OpenAI 新版的 developer 角色，`ChatRole` 不认识。
   修法：`openai_compat.rs` 中 `ChatRole::System` 加 `#[serde(alias = "developer")]`。
2. **真实用户消息被丢掉（text 为空）**：dsh 在用户消息后面还追加两条 user 注入（runtime context 快照、`<system-reminder>` skill 列表）。服务端只取「最后一条 user」，剥掉 reminder 后就成了空串。
   修法：取最后一个 assistant/tool 之后的**全部** user 消息；Seat 走 D2 的原样上下文，人类版过滤纯注入块后再拼接。
3. **会话合并**：Qoder、dsh 不带任何会话 ID，兜底的 key 是 `prm:<system_prompt 指纹>:<client>`，同一客户端的所有会话都合成一个；与之相对，系统提示词不同的辅助请求反倒被拆成了独立会话。
   修法见 §3 的「历史连续性」方案（D3）。
4. **辅助请求混进主会话**：Qoder 的「技能复盘」请求和主对话共用 system_prompt，于是落进主会话，可能与用户真实的下一轮抢锁（409）并污染历史。

### P1 — 体验差、噪音大
5. **重复推送**：调用方每轮都带完整历史，服务端把历史里的 `role:tool` 和旧 user 消息当成新的再推一遍。实测同一个 tool.result 推了 4 次（每次约 50KB），同一条 user 消息推了 3 次。
   修法：按会话记录「已见消息水位线」，或按 tool_call_id 和消息位置去重。
6. **`capability.updated` 每轮都推**：工具表没变也推。改为工具表 hash 变化时才推。
7. **`capability.updated` 的 conversation_id 填成了 human_id**（如 `hum_hark`），语义错误。
8. **context / capabilities 按 agent 存，不按会话或请求存**：多窗口、辅助请求会互相覆盖 system_prompt 和工具表。应答方因此不知道当前这个请求要什么格式，例如 Qoder 标题生成要 `{"title":...}`，我回了纯文本后它每 20 秒重试一次。
   修法：每个 `message.received` 附带本请求的 system_prompt 摘要、response_format、tools 的 hash；或者直接按 D2 提供 messages。
9. **「[OpenHuman 提示]: 人类专家当前在线，消息已送达，正在等待回复...」**（`api/openai.rs` 约 490 行）在 Seat 上仍然注入，导致调用方历史里我的每条回复都带着这个前缀（D4）。
10. **应答方看不到历史**：Seat 只收到最后一条 user 消息。需要 `GET /v1/seat/history/{conversation_id}`，或在 full 视图里带上本轮 messages（D2）。
11. **辅助请求识别**：标题生成、输入框建议、技能复盘都被当成用户消息推送。应给它们标上 `kind: auxiliary`（可按 system_prompt 指纹、无 tools、小 max_tokens 等判断），或允许应答方配置自动处理。

### P2 — 功能补全
12. **`/v1/models` 缺模型元数据**：dsh 能自动拿到模型列表 `openhuman-human`，但拿不到上下文长度、思考深度等配置。应返回 context_length、max_output_tokens、推理和工具能力。修之前需要查 dsh 实际读取哪些字段（相关插件：`dsh-llm`、`dsh-deepseek-llm-api-extensions`、`agent-default-model`）。
    同一根因的推测：**dsh PTC 模式对 openhuman-human 静默降级**（工具表和 system_prompt 里都没有 PTC 入口），dsh 很可能按模型或 provider 的能力决定是否启用 PTC。
13. **客户端识别**：Qoder 只识别出 `user_agent: undici`。可用 system_prompt 开头的 "You are a Qoder agent" 做指纹。
14. **compact 视图的工具没有参数名**：只给 id 和 200 字描述，必须再拉 full（WorkBuddy 约 107KB）。建议 compact 附带 required 参数名。
15. **图片**：以 data URL 形式进入 full 视图，识别正常；compact 视图只给 `image_count`。建议增加 `GET /v1/seat/attachments/{message_id}/{n}`。
16. **compact 视图的 tool.result 在约 25KB 处截断**（`truncated:true`），行为合理，需要写进文档。
17. **`/v1/seat/send` 要求手拼 `event_type`**：提供简化形式 `{conversation_id, text}`。
18. **一轮结束后应答方无法主动发消息**（OpenAI 协议的限制）。可考虑排队，在下一轮开头送达。
19. **重启后 seat 队列和 cursor 丢失**（内存态），长轮询的 after 游标会失效。
20. **应答方不是常驻在线**：靠后台长轮询，间隙超过 TTL 180 秒就会被判离线。需要推送或 webhook 唤醒机制。

### 非本项目
- WorkBuddy 的 Glob 在大目录上 30 秒超时（客户端问题）。
- 生产副本 `tests/ws_chain.rs` 的旧 clippy lint。

## 3. 新会话识别方案（D3，对应问题 3、4、11）

优先级：显式 ID（`x-openhuman-conversation-id` / `x-conversation-id` / body.conversation / session 头 / `user` / metadata）**>** 历史连续性 **>** 指纹兜底。

历史连续性判断：
1. 服务端为每个会话记录自己发出的 assistant 回复（hash），以及首条真实 user 消息的 hash。
2. 新请求进来时：如果历史里包含某个已有会话最近一条回复的 hash，就是该会话的延续，沿用原 ID。
3. 如果历史里一条我们的回复都没有，并且只有首条 user 消息，就开新会话。
4. 如果历史和已存记录对不上（用户编辑了历史、`/compact`、回退），就开新会话（可标 `forked_from`）。
5. 开新会话时推送 `conversation.started {conversation_id, client, first_message}`，**Seat 和 /ws 都推**，Flutter 新建会话卡片。

## 4. 各客户端实测

| 客户端 | 识别 | 工具 | system_prompt | 会话 ID | 结果 |
|---|---|---|---|---|---|
| WorkBuddy 5.8.3 | ✅ ide_name=WorkBuddy | 24 个（Bash/Read/Glob/Edit/Grep/PowerShell…） | 约 49K（含个人记忆） | ✅ x-conversation-id | 消息干净；Bash 往返正常（cwd `C:/Users/Juwan/WorkBuddy/<session>`）；Glob 大目录超时 |
| Qoder | ❌ 只识别出 undici | 26 个（含 ImageGen、mcp_*、Task*） | 约 27.5K | ❌ prm 指纹 | Bash、图片正常；辅助请求多（建议引擎、标题要 JSON、技能复盘要 JSON） |
| DeepSeek Harness 0.2.0-rc.1 标准模式 | ✅ UA | 29 个，全小写（pwsh/read/edit/glob…，无 Bash） | 约 5.8K | ❌ prm 指纹 | 默认 developer 角色导致 422；关掉后 pwsh 正常 |
| dsh 创造模式 | ✅ | 33 个（+plugin_manager、cordis_inspect_*、subagent） | 约 5.9K | ❌ | cordis_inspect_list/query、plugin_manager list 正常（只读；runtime 为 danger-full-access，审批自动拒绝）；用户原话被吞（问题 2） |
| dsh PTC 模式 | ✅ | 与创造模式相同，无 PTC 入口 | 约 5.9K | ❌ | 疑似降级（问题 12）；批量统计改用 pwsh 管道完成 |

请求参数观察：dsh 发送 `chat_template_kwargs.reasoning_effort=max`、`max_completion_tokens=32768`、`stream_options.include_usage`。

## 5. 调试技巧

- 查看调用方实际发出的请求：`docker exec openhuman-server ls -t observations`，文件里有 headers 和 body，auth 已打码。
- 想知道某个请求要什么格式：`GET /v1/seat/capabilities?view=full` → `context.system_prompt`（只保留最近一次，见问题 8）。
- 图片：`GET /v1/seat/inbox?view=full` 里 `data.images[]` 是 data URL。

## 0c. 用户设计决定（2026-10-21 09:05 CST，WorkBuddy 对话中）
- 服务器默认**无记录**：调用方每次发来的全量上下文就是唯一事实来源，每轮现场解析；原先实现没理解这个意图，要改回来。
- 用户想留档时，通过一个「保存」按键保存当时的会话记录（真人端是按钮，Seat 端是接口）。
- Hark 提出的方案：每会话内存保留「最后请求快照 + 出站队列 + 水位线」；history/时间线从快照解析；新会话识别改用快照前缀比对。用户让 Hark 自定：出站队列也只放内存。用户要求先别做，先继续测 Qoder 和 dsh。
- 同轮新发现：history 角色标签反了（调用方=agent、应答方=human），回复 role 为空，时间为 UTC；Seat 重新接入时 drain 会把旧 tool 输出当成 message.received；03:16 的消息因为没有唤醒机制一直没回。
