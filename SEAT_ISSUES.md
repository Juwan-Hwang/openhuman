# Agent Seat 使用问题清单（2026-10-21，待统一修复）

已修复并部署（02:48）：waiting_turns 残留关闭通道 / 跨租户泄露；Seat 接入不再注入“人类专家已上线”（/ws 真人不变）。

待修：
1. `/v1/seat/send` 需要手拼底层 `event_type`，不直观；应提供简单的 `{conversation_id, text}` 形式或明确文档。
2. 一轮结束后应答方无法主动发消息给调用方（OpenAI 协议本身限制；可考虑排队到下一轮开头）。
3. 服务重启后 seat 队列/cursor 全部丢失（内存态），长轮询的 after 游标失效。
4. capabilities/context 按 agent 存，不按 conversation：同一 agent 多个并发会话（WorkBuddy 多窗口）会互相覆盖 system_prompt/工具表。
5. `capability.updated` 事件的 conversation_id 填的是 human_id（hum_hark），语义错误。
6. compact 视图的工具只有 id + 200 字描述，没有参数名；要正确调用必须拉 full（WorkBuddy 24 个工具约 107KB）。建议 compact 附带 required 参数名列表。
7. ~~system_prompt 脱敏~~ 用户决定（2026-10-21）：不脱敏，接入即有权看原样。不修。
8. 应答方（Hark）不是常驻：靠后台长轮询（单次 ≤ ~20 分钟），间隙超过 TTL 180s 即掉线；需要推送/webhook 唤醒机制。
9. 非项目问题：WorkBuddy 的 Glob 在大目录 30s 超时。
10. tests/ws_chain.rs（生产副本）有旧的 clippy `redundant_locals` lint。

## 各客户端体验
- WorkBuddy 5.8.3：消息干净；context.runtime 识别为 WorkBuddy；24 个工具；Bash 往返正常。
- Qoder：消息干净；Bash 往返正常（pwd 正常返回）；26 个工具，system_prompt 27.5K 字符。
  11. runtime 只识别出 `user_agent: undici`，没认出 Qoder（ide_name 为空）。normalize/runtime 检测需加 Qoder 指纹（可从 system_prompt 开头 "You are a Qoder agent" 识别）。
  12. Qoder 的辅助请求（输入框建议引擎、疑似标题生成）也走 /v1/chat/completions，被当成新会话推给应答方：一次用户消息产生 2~3 个会话。且 context 只存最新一次，被辅助请求的 system_prompt 覆盖。需要识别辅助调用（system_prompt 指纹/无 tools/max_tokens 小），在 inbox 标记 `kind: auxiliary`，或允许配置自动处理。
  13. 会话 key `prm:<system_prompt 指纹>:<client>`：Qoder 的辅助请求 system_prompt 不同，所以各自成会话；主会话是否稳定待观察。
  14. 投递时注入的 “[OpenHuman 提示]: 人类专家当前在线，消息已送达，正在等待回复...”（openai.rs:490）对 Seat 仍生效，混入了 Qoder 的转写。按用户规则：只有应答方是 agent seat 时关闭，真人 /ws 保留。
  15. 图片：Qoder 图片以 data URL 进 full 视图，可正常识别。compact 只给 image_count，需另拉 full（会连带拿到全部历史大字段）；建议加 `GET /v1/seat/attachments/{message_id}/{n}`。
  16. Qoder 每轮额外发一个只含首条用户消息的请求（疑似标题生成），反复进入同一辅助会话。属于 12 的同类。
  17. Qoder 的「技能复盘」辅助请求（要求返回 JSON suggestions）与主对话同 system_prompt，于是落进**主会话**，会和用户真实下一轮抢同一 conversation（并发 409 风险）并混进主会话历史。12 的严重版。
  18. Qoder 标题请求要求 JSON（{"title":...}），我回纯文本后它每 ~20s 重试一次。应答方在 compact inbox 里看不到该请求的 system_prompt/response_format，就无从得知格式。建议 message.received 附带每条请求自己的 system_prompt 摘要 + response_format（对应 #4）。
  19. 同一个 tool.result（call_…196）在后续每轮请求里被重复推送（cursor 32/46/63）：调用方每次带完整历史，服务端把历史里的 role:tool 又当新结果路由一遍。应按 tool_call_id 去重，只推一次。
  20. 每轮都重复推送 capability.updated（工具表没变也推），噪音大。应只在工具表 hash 变化时推。
  21. **调用方兼容性 bug（阻塞）**：DeepSeek harness (dsh) 发送 OpenAI 新版 `role: "developer"`，服务端 422「unknown variant developer」。修法：openai_compat.rs ChatRole::System 加 `#[serde(alias = "developer")]`（一行）。
- DeepSeek Harness 0.2.0-rc.1：关掉 developer 角色后可用（#21 仍需修，否则默认配置 422）。runtime 正确识别（UA deepseek-harness）；29 个工具，工具名小写（pwsh/read/edit…，无 Bash）；system_prompt 5.8K；pwsh 往返正常（cwd C:\Users\Juwan\.dsh\ungrouped，PS 7.6.7）。
  22. dsh：工具结果回传那一轮，同一条用户消息（"现在是不是可以了…"）被重新推成新的 message.received（cursor 86 与 88，message_id 不同）。去重应按内容/历史位置判断，带 role:tool 的续轮不应重推旧 user 消息。
  23. 应答方只能看到"最新一条 user 消息"。调用方每轮都带完整历史（dsh 本轮 9 条：system + 首条失败的 user + runtime-context 注入 + skill 提醒 + …），但 seat 拿不到历史和中间的 user 注入（如 dsh 的 runtime context / skill system-reminder）。建议 inbox 提供 `GET /v1/seat/history/{conversation_id}`，或 full 视图带本轮 messages。目前只能靠服务器 observation 文件看到。
  24. 历史里我的回复被存成带「[OpenHuman 提示]: 人类专家当前在线…」前缀（#14 的后果），调用方模型会把这段当成我说的话。
  25. **严重**：dsh 创造模式下，用户真实消息之后还追加了两条 user 注入（runtime context 快照、skill 列表 <system-reminder>）。服务端只取"最后一条 user"→ 剥掉 system-reminder 后为空，推给应答方的 message.received text=""，真实问题丢失。修法：取最后一个 assistant/tool 之后的所有 user 消息，过滤纯注入块后拼接；或识别"真实人类消息"。
  26. 用户需求：dsh 配置模型时能自动拉到 openhuman-human，但拉不到上下文长度、思考深度等配置。/v1/models 应返回 context_length / max_output_tokens / 推理能力等元数据（参考 OpenRouter/DeepSeek 的字段：context_length、max_completion_tokens、supported_parameters 等，需查 dsh 读取哪些字段）。
- dsh 创造模式：多出 plugin_manager、cordis_inspect_list/query、subagent；runtime 为 danger-full-access 且审批自动拒绝。cordis_inspect_list 往返正常。
  27. 设计结论（用户提议 2026-10-21）：剥离/归一化是为人类做的，agent 应答方不需要。Seat 应拿原样的本轮 messages（至少"上一个 assistant 之后的全部消息"，保留 role 和 system-reminder），人类 /ws 仍走剥离版。可一并解决 #23 #25，部分解决 #12/#18（能看到每个请求自己的 system prompt）。
- dsh bundle 中与 #26 相关：dsh-llm、dsh-deepseek-llm-api-extensions、agent-default-model。修 #26 时去查 dsh 源码里 provider 自动获取读的是 /v1/models 的哪些字段。
  - #19/#22 加重确认：dsh 一轮里有 3 次工具往返，每次续轮请求都会把之前所有 tool.result（每个约 50KB）和那条 user 消息重新推一遍。一轮下来同一条消息推了 3 次，同一个 tool.result 推了 4 次，inbox 一次就超过 100KB。修 #27 时要用"已见消息水位线"按会话去重。
  - compact 视图里 tool.result 带 truncated:true，在约 25KB 处截断（合理，但需要文档说明，要全文得看 full）。
- dsh PTC 模式：请求里的工具表和创造模式完全相同（33 个），没有任何 ptc/代码执行类工具，system_prompt 也没提 PTC。推测 dsh 只对支持 PTC 的 provider（官方 DeepSeek）启用，对 openhuman-human 会静默降级。可能与 #26 相关：/v1/models 没声明能力，dsh 就不会开启。请求参数里带了 chat_template_kwargs.reasoning_effort=max、max_completion_tokens=32768。
  28. dsh 新开会话后历史清零，但 conversation_id 不变（仍为 cnv_…0f6）。会话 key 取的是 prm:<system_prompt 指纹>，同一客户端的不同会话会被合并成一个。#13 的实例。
  29. 用户需求（2026-10-21）：调用方开新会话时，应答方（agent seat 和 Flutter 真人两边都要）能识别出这是新会话并区分开。
     现状：WorkBuddy 带 x-conversation-id，能分（session_key=hdr:…）；Qoder 和 dsh 不带任何会话 id（dsh 的请求头里只有 stainless 头），只能退回 prm:<system_prompt 指纹>:<client>，结果同一客户端的所有会话都会合并。
     方案：在 prm/cli 兜底层加“历史连续性”判断。服务端记得自己在每个会话里发出过的 assistant 回复，新请求的历史如果是已存会话的延续（里面包含我们最近一条回复，或者首条真实 user 消息相同且历史长度不比上次短），就沿用原会话，否则开新的 conversation_id。分叉或回退（用户编辑历史、/compact）时也按新会话处理，或者标记成 fork。新会话推一个 `conversation.started` 事件（带客户端名和首条消息），Seat 和 /ws 都要推，Flutter 那边新建一个会话卡片。
