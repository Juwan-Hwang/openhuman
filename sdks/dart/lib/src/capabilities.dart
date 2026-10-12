/// OpenHuman Dart SDK — Agent capability, context & tool invocation models.
///
/// This file implements the Phase 7 capability layer, aligned 1:1 with
/// the Rust server implementation:
///
///   - `server/src/model/agent_capability.rs`  — AgentCapability + CapabilityManifest
///   - `server/src/model/agent_context.rs`     — AgentContext
///   - `server/src/model/tool_invocation.rs`   — ToolInvoke + ToolResult + InvocationStatus
///
/// and the protocol specification:
///
///   - `protocol/internal-model/capability.md`  — §3 AgentCapability,
///     §4 AgentContext, §9 Tool Invocation Model
///
/// # Design Principle
///
/// OpenHuman is a **transport and visualization layer** for tool invocation.
/// It does **not** execute tools. It carries `tool.invoke` from the human
/// to the agent and relays `tool.result` back. The agent owns execution;
/// the human owns the decision to invoke; OpenHuman owns the pipe.
///
/// # OpenAI Compatibility
///
/// [AgentCapability] is structurally compatible with OpenAI's `tools` /
/// `functions` format: `id` → `function.name`, `description` → direct,
/// `inputSchema` → `function.parameters`. This allows agents that already
/// declare OpenAI tools to publish them to OpenHuman without transformation.
///
/// # JSON Wire Format
///
/// All Rust structs use `snake_case` field names. Dart models use
/// `@JsonKey(name: 'snake_case')` to map to camelCase Dart fields.
/// Optional fields use `#[serde(skip_serializing_if = "Option::is_none")]`
/// in Rust, which maps to `@JsonKey(includeIfNull: false)` in Dart.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'capabilities.freezed.dart';
part 'capabilities.g.dart';

// ═════════════════════════════════════════════════════════════════
//  Invocation Status
// ═════════════════════════════════════════════════════════════════

/// Status of a tool invocation.
///
/// Aligned with Rust `server/src/model/tool_invocation.rs::InvocationStatus`:
/// ```rust
/// #[serde(rename_all = "lowercase")]
/// pub enum InvocationStatus {
///     Pending,
///     Success,
///     Error,
///     Cancelled,
///     Timeout,
/// }
/// ```
///
/// JSON wire format: `"pending"` / `"success"` / `"error"` /
/// `"cancelled"` / `"timeout"`.
///
/// See: `protocol/internal-model/capability.md §9`
@JsonEnum(alwaysCreate: true, fieldRename: FieldRename.none)
enum InvocationStatus {
  /// Request sent, awaiting agent response.
  @JsonValue('pending')
  pending,

  /// Agent executed successfully, result available.
  @JsonValue('success')
  success,

  /// Agent execution failed.
  @JsonValue('error')
  error,

  /// Human cancelled the request.
  @JsonValue('cancelled')
  cancelled,

  /// Agent did not respond within timeout.
  @JsonValue('timeout')
  timeout,
}

// ═════════════════════════════════════════════════════════════════
//  Agent Capability
// ═════════════════════════════════════════════════════════════════

/// A single tool/capability that an agent exposes to the human.
///
/// OpenHuman **does not execute** the tool — it transports the
/// `tool.invoke` request to the agent and relays the `tool.result` back.
///
/// Aligned with Rust `server/src/model/agent_capability.rs::AgentCapability`:
/// ```rust
/// pub struct AgentCapability {
///     pub id: String,
///     pub name: String,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub description: Option<String>,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub category: Option<String>,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub input_schema: Option<Value>,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub output_schema: Option<Value>,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub ui_schema: Option<Value>,
///     #[serde(default)]
///     pub permissions: Vec<String>,
///     #[serde(default)]
///     pub metadata: HashMap<String, Value>,
/// }
/// ```
///
/// JSON wire format:
/// ```json
/// {
///   "id": "github_create_issue",
///   "name": "Create GitHub Issue",
///   "description": "Creates an issue in a GitHub repository.",
///   "category": "github",
///   "input_schema": { "type": "object", ... },
///   "output_schema": { "type": "object", ... },
///   "ui_schema": { "component": "form", ... },
///   "permissions": ["repo:issues:write"],
///   "metadata": { "icon": "github" }
/// }
/// ```
///
/// See: `protocol/internal-model/capability.md §3`
@freezed
class AgentCapability with _$AgentCapability {
  const factory AgentCapability({
    /// Unique tool identifier (kebab-case, e.g., `github_create_issue`).
    required String id,

    /// Human-readable display name.
    required String name,

    /// What this tool does. Omitted from JSON when `null`.
    @JsonKey(includeIfNull: false) String? description,

    /// Grouping label (`github`, `terminal`, `browser`, ...).
    @JsonKey(includeIfNull: false) String? category,

    /// JSON Schema describing the expected input parameters.
    @JsonKey(name: 'input_schema', includeIfNull: false)
    Map<String, dynamic>? inputSchema,

    /// JSON Schema describing the output shape.
    @JsonKey(name: 'output_schema', includeIfNull: false)
    Map<String, dynamic>? outputSchema,

    /// UI rendering hints for the human client (form fields, widgets, ...).
    @JsonKey(name: 'ui_schema', includeIfNull: false)
    Map<String, dynamic>? uiSchema,

    /// Required permission scopes (e.g., `repo:issues:write`).
    @Default(<String>[]) List<String> permissions,

    /// Free-form metadata bag.
    @Default(<String, dynamic>{}) Map<String, dynamic> metadata,
  }) = _AgentCapability;

  factory AgentCapability.fromJson(Map<String, dynamic> json) =>
      _$AgentCapabilityFromJson(json);
}

// ═════════════════════════════════════════════════════════════════
//  Agent Context
// ═════════════════════════════════════════════════════════════════

/// Non-sensitive runtime context for an agent.
///
/// Provides human-facing metadata about the agent's working environment:
/// system prompt in use, model details, runtime platform, repository/branch,
/// etc. It **must never** contain secrets, API tokens, or any sensitive
/// credential.
///
/// Aligned with Rust `server/src/model/agent_context.rs::AgentContext`:
/// ```rust
/// pub struct AgentContext {
///     pub agent_id: String,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub system_prompt: Option<String>,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub model: Option<Value>,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub runtime: Option<Value>,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub environment: Option<Value>,
/// }
/// ```
///
/// JSON wire format:
/// ```json
/// {
///   "agent_id": "agt_demo_codex",
///   "system_prompt": "You are a coding assistant...",
///   "model": { "name": "gpt-4o", "provider": "openai" },
///   "runtime": { "platform": "linux", "version": "0.1.0" },
///   "environment": { "repo": "openhuman/openhuman", "branch": "main" }
/// }
/// ```
///
/// See: `protocol/internal-model/capability.md §4`
@freezed
class AgentContext with _$AgentContext {
  const factory AgentContext({
    /// The agent this context belongs to.
    @JsonKey(name: 'agent_id') required String agentId,

    /// The system prompt in use (may be truncated for display).
    @JsonKey(name: 'system_prompt', includeIfNull: false) String? systemPrompt,

    /// Model metadata: `{ name, provider, max_tokens }`.
    @JsonKey(includeIfNull: false) Map<String, dynamic>? model,

    /// Runtime info: `{ platform, version, session_id }`.
    @JsonKey(includeIfNull: false) Map<String, dynamic>? runtime,

    /// Environment info: `{ repo, branch, working_directory }`.
    @JsonKey(includeIfNull: false) Map<String, dynamic>? environment,
  }) = _AgentContext;

  factory AgentContext.fromJson(Map<String, dynamic> json) =>
      _$AgentContextFromJson(json);
}

// ═════════════════════════════════════════════════════════════════
//  Tool Invocation
// ═════════════════════════════════════════════════════════════════

/// A `tool.invoke` request — sent by the human, routed to the agent.
///
/// OpenHuman is a **transport layer** for tool invocation. It does not
/// execute tools — it carries `tool.invoke` from the human to the agent
/// and relays `tool.result` back.
///
/// Aligned with Rust `server/src/model/tool_invocation.rs::ToolInvoke`:
/// ```rust
/// pub struct ToolInvoke {
///     pub invocation_id: String,
///     pub tool_id: String,
///     pub input: Value,
/// }
/// ```
///
/// JSON wire format:
/// ```json
/// {
///   "invocation_id": "inv_0189abc123",
///   "tool_id": "github_create_issue",
///   "input": {
///     "repo": "openhuman/openhuman",
///     "title": "Bug: login fails",
///     "body": "Steps to reproduce..."
///   }
/// }
/// ```
///
/// See: `protocol/internal-model/capability.md §9.1`
@freezed
class ToolInvoke with _$ToolInvoke {
  const factory ToolInvoke({
    /// Unique invocation ID (used to correlate request → result).
    @JsonKey(name: 'invocation_id') required String invocationId,

    /// The tool/capability being invoked.
    @JsonKey(name: 'tool_id') required String toolId,

    /// Input parameters conforming to `AgentCapability.inputSchema`.
    required dynamic input,
  }) = _ToolInvoke;

  factory ToolInvoke.fromJson(Map<String, dynamic> json) =>
      _$ToolInvokeFromJson(json);
}

/// A `tool.result` response — sent by the agent, routed to the human.
///
/// Aligned with Rust `server/src/model/tool_invocation.rs::ToolResult`:
/// ```rust
/// pub struct ToolResult {
///     pub invocation_id: String,
///     pub tool_id: String,
///     pub status: InvocationStatus,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub output: Option<Value>,
///     #[serde(skip_serializing_if = "Option::is_none")]
///     pub error: Option<String>,
/// }
/// ```
///
/// JSON wire format:
/// ```json
/// {
///   "invocation_id": "inv_0189abc123",
///   "tool_id": "github_create_issue",
///   "status": "success",
///   "output": { "issue_number": 42, "html_url": "https://..." },
///   "error": null
/// }
/// ```
///
/// See: `protocol/internal-model/capability.md §9.2`
@freezed
class ToolResult with _$ToolResult {
  const factory ToolResult({
    /// Correlates to the original `ToolInvoke.invocationId`.
    @JsonKey(name: 'invocation_id') required String invocationId,

    /// The tool that was invoked.
    @JsonKey(name: 'tool_id') required String toolId,

    /// Outcome of the invocation.
    required InvocationStatus status,

    /// Output data conforming to `AgentCapability.outputSchema`.
    /// Omitted from JSON when `null`.
    @JsonKey(includeIfNull: false) dynamic output,

    /// Error message if `status == error`. Omitted from JSON when `null`.
    @JsonKey(includeIfNull: false) String? error,
  }) = _ToolResult;

  factory ToolResult.fromJson(Map<String, dynamic> json) =>
      _$ToolResultFromJson(json);
}

// ═════════════════════════════════════════════════════════════════
//  Capability Manifest
// ═════════════════════════════════════════════════════════════════
//
// `CapabilityManifest` is defined in `events.dart` as part of the
// WebSocket event payload model (it carries `toWireJson()` for the
// `capability.manifest` event type). That version uses `Map<String,
// dynamic>` for self-containment before this file's strong types
// existed.
//
// The Rust server's `agent_capability.rs::CapabilityManifest` uses
// `Vec<AgentCapability>` and `Option<AgentContext>`. The events.dart
// version is wire-compatible because JSON is structurally typed — the
// weak `List<Map<String, dynamic>>` accepts the same JSON shapes.
//
// If a strongly-typed manifest is needed at the SDK API layer, it can
// be constructed by parsing each map via `AgentCapability.fromJson`.
