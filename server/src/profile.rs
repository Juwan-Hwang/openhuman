//! Agent Profile Extractor — derives an agent's capabilities and context
//! from the standard OpenAI API request.
//!
//! Phase 7.1.1: This replaces the Phase 7 WebSocket `capability.manifest`
//! as the **primary** capability discovery path. Any OpenAI-compatible
//! agent automatically gets its tools registered without needing an
//! OpenHuman-specific SDK or WebSocket protocol.
//!
//! # Data Flow
//!
//! ```text
//! POST /v1/chat/completions
//!     { model, messages, tools: [...], ... }
//!         |
//!         v
//! extract_profile(headers, request, agent_id)
//!         |
//!         v
//! AgentProfile { agent_id, client_type, model, system_prompt, tools, runtime }
//!         |
//!         v
//! CapabilityRegistry::set_capabilities()  (upsert on every request)
//! ContextRepository::set_context()         (upsert on every request)
//! ```
//!
//! # Client Type Detection
//!
//! `client_type` is a **heuristic** — it should never be relied upon for
//! security or logic decisions. It is metadata for the human-facing UI.
//! Detection uses multiple signals (User-Agent, x-stainless-*, system prompt
//! keywords) based on Phase 8 observation data.

use std::collections::HashMap;

use axum::http::HeaderMap;
use serde::Serialize;
use serde_json::Value;

use crate::model::agent_capability::AgentCapability;
use crate::model::agent_context::AgentContext;
use crate::openai_compat::{ChatCompletionRequest, ChatRole};

/// Heuristic client type classification.
///
/// Derived from HTTP headers and system prompt content. This is metadata
/// only — **do not** use for security decisions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ClientType {
    /// Claude Code (Anthropic CLI). Identified by `cc_version=` in system prompt.
    ClaudeCode,
    /// Trae / TraeWork (ByteDance). Identified by `User-Agent: hertz`.
    Trae,
    /// WorkBuddy / CodeBuddy. Identified by `x-ide-name: WorkBuddy`.
    WorkBuddy,
    /// OpenAI Codex CLI. Identified by `codex` in User-Agent.
    Codex,
    /// Cursor. Identified by `cursor` in User-Agent.
    Cursor,
    /// Any other OpenAI-compatible client.
    Unknown,
}

impl std::fmt::Display for ClientType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ClaudeCode => write!(f, "claude_code"),
            Self::Trae => write!(f, "trae"),
            Self::WorkBuddy => write!(f, "workbuddy"),
            Self::Codex => write!(f, "codex"),
            Self::Cursor => write!(f, "cursor"),
            Self::Unknown => write!(f, "unknown"),
        }
    }
}

/// Runtime metadata extracted from HTTP headers.
#[derive(Debug, Clone, Serialize)]
pub struct AgentRuntime {
    /// Raw `User-Agent` header value.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_agent: Option<String>,
    /// Stainless SDK version (if present, indicates OpenAI JS SDK).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stainless_version: Option<String>,
    /// IDE name (if present, indicates an IDE-integrated agent).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ide_name: Option<String>,
    /// Heuristic framework detection.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detected_framework: Option<String>,
}

/// The complete profile of an agent, extracted from a single HTTP request.
///
/// Built fresh on every `POST /v1/chat/completions`. The caller is
/// responsible for upserting into `CapabilityRepository` and
/// `ContextRepository`.
#[derive(Debug, Clone)]
pub struct AgentProfile {
    /// The agent ID from the API key resolution.
    pub agent_id: String,
    /// Heuristic client type (metadata only).
    pub client_type: ClientType,
    /// The model name from the request body.
    pub model: Option<String>,
    /// Combined system messages (truncated for storage).
    pub system_prompt: Option<String>,
    /// Capabilities extracted from the `tools[]` array.
    pub capabilities: Vec<AgentCapability>,
    /// Runtime metadata from HTTP headers.
    pub runtime: AgentRuntime,
}

impl AgentProfile {
    /// Extract a full agent profile from an HTTP request.
    ///
    /// This function is pure — no side effects. The caller is responsible
    /// for persisting the results.
    pub fn extract(headers: &HeaderMap, req: &ChatCompletionRequest, agent_id: &str) -> Self {
        let system_prompt = extract_system_prompt(req);
        let client_type = detect_client_type(headers, &system_prompt);
        let capabilities = extract_capabilities(req.tools.as_ref());
        let runtime = extract_runtime(headers, &client_type);

        Self {
            agent_id: agent_id.to_string(),
            client_type,
            model: req.model.clone(),
            system_prompt,
            capabilities,
            runtime,
        }
    }

    /// Convert the profile's context portion to an `AgentContext` for storage.
    pub fn to_context(&self) -> AgentContext {
        AgentContext {
            agent_id: self.agent_id.clone(),
            system_prompt: self.system_prompt.clone(),
            model: self
                .model
                .as_ref()
                .map(|m| serde_json::json!({ "name": m })),
            runtime: Some(serde_json::to_value(&self.runtime).unwrap_or_default()),
            environment: None,
        }
    }
}

/// Extract all system messages from the request and combine them.
fn extract_system_prompt(req: &ChatCompletionRequest) -> Option<String> {
    let mut parts: Vec<String> = Vec::new();
    for msg in &req.messages {
        if msg.role == ChatRole::System {
            let text = msg.content.to_text();
            if !text.is_empty() {
                parts.push(text);
            }
        }
    }
    if parts.is_empty() {
        None
    } else {
        Some(parts.join("\n"))
    }
}

/// Detect the client type using multi-signal heuristic.
///
/// Priority:
/// 1. `x-ide-name: WorkBuddy` → WorkBuddy
/// 2. `User-Agent: hertz` → Trae
/// 3. `User-Agent` containing `WorkBuddy` → WorkBuddy
/// 4. `User-Agent` containing `codex` → Codex
/// 5. `User-Agent` containing `cursor` → Cursor
/// 6. System prompt contains `cc_version=` or `Claude Agent SDK` → ClaudeCode
/// 7. Otherwise → Unknown
fn detect_client_type(headers: &HeaderMap, system_prompt: &Option<String>) -> ClientType {
    // WorkBuddy: x-ide-name header
    if let Some(ide) = headers.get("x-ide-name").and_then(|v| v.to_str().ok()) {
        if ide.eq_ignore_ascii_case("WorkBuddy") {
            return ClientType::WorkBuddy;
        }
    }

    // Trae: User-Agent: hertz
    if let Some(ua) = headers.get("user-agent").and_then(|v| v.to_str().ok()) {
        if ua == "hertz" {
            return ClientType::Trae;
        }
        let lower = ua.to_lowercase();
        // WorkBuddy also sends User-Agent with "WorkBuddy"
        if lower.contains("workbuddy") || lower.contains("codebuddy") {
            return ClientType::WorkBuddy;
        }
        if lower.contains("codex") {
            return ClientType::Codex;
        }
        if lower.contains("cursor") {
            return ClientType::Cursor;
        }
    }

    // Claude Code: system prompt contains billing header
    if let Some(prompt) = system_prompt {
        if prompt.contains("cc_version=") || prompt.contains("Claude Agent SDK") {
            return ClientType::ClaudeCode;
        }
    }

    ClientType::Unknown
}

/// Extract runtime metadata from HTTP headers.
fn extract_runtime(headers: &HeaderMap, client_type: &ClientType) -> AgentRuntime {
    let user_agent = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let stainless_version = headers
        .get("x-stainless-package-version")
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let ide_name = headers
        .get("x-ide-name")
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let detected_framework = match client_type {
        ClientType::Trae => Some("Hertz (ByteDance)".to_string()),
        ClientType::WorkBuddy => stainless_version
            .as_ref()
            .map(|v| format!("Stainless JS SDK v{}", v))
            .or_else(|| Some("WorkBuddy CLI".to_string())),
        ClientType::ClaudeCode => Some("Claude Agent SDK".to_string()),
        ClientType::Codex => Some("Codex CLI".to_string()),
        ClientType::Cursor => Some("Cursor".to_string()),
        ClientType::Unknown => stainless_version
            .as_ref()
            .map(|v| format!("Stainless JS SDK v{}", v)),
    };

    AgentRuntime {
        user_agent,
        stainless_version,
        ide_name,
        detected_framework,
    }
}

/// Extract capabilities from the OpenAI `tools[]` array.
///
/// Each tool in the array is expected to have:
/// ```json
/// { "type": "function", "function": { "name": "...", "description": "...", "parameters": {...} } }
/// ```
///
/// Returns an empty vec if `tools` is missing, null, or not an array.
pub fn extract_capabilities(tools: Option<&Value>) -> Vec<AgentCapability> {
    let arr = match tools {
        Some(Value::Array(a)) => a,
        _ => return Vec::new(),
    };

    arr.iter()
        .filter_map(|tool| {
            let func = tool.get("function")?;
            let name = func.get("name")?.as_str()?;
            let description = func
                .get("description")
                .and_then(|d| d.as_str())
                .map(String::from);
            let input_schema = func.get("parameters").cloned();

            Some(AgentCapability {
                id: name.to_string(),
                name: name.to_string(),
                description,
                category: infer_category(name),
                input_schema,
                output_schema: None,
                ui_schema: None,
                permissions: Vec::new(),
                metadata: HashMap::new(),
            })
        })
        .collect()
}

/// Heuristically infer a tool's category from its name.
///
/// This is a display hint only — not authoritative.
fn infer_category(name: &str) -> Option<String> {
    match name {
        // Terminal / shell
        "Bash" | "PowerShell" | "RunCommand" => Some("terminal".into()),
        // Filesystem
        "Read" | "Write" | "Edit" | "Glob" | "Grep" | "LS" | "SearchReplace" | "DeleteFile" => {
            Some("filesystem".into())
        }
        // Web
        "WebSearch" | "WebFetch" => Some("web".into()),
        // Sub-agent / task delegation
        "Task" | "Agent" => Some("subagent".into()),
        // Skills
        "Skill" => Some("skill".into()),
        // Task management
        "TaskCreate" | "TaskGet" | "TaskUpdate" | "TaskList" | "TaskOutput" | "TodoWrite" => {
            Some("task_management".into())
        }
        // UI / visualization
        "present_files" | "show_widget" | "read_me" | "PureShowWidget" | "OpenPreview" => {
            Some("ui".into())
        }
        // Scheduling
        "Schedule" | "automation_update" => Some("scheduling".into()),
        // Communication
        "AskUserQuestion" | "NotifyUser" | "SendMessage" => Some("communication".into()),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_capabilities_from_claude_code() {
        let tools = serde_json::json!([
            {"type": "function", "function": {"name": "Bash", "description": "execute shell commands", "parameters": {"type": "object", "properties": {"command": {"type": "string"}}}}},
            {"type": "function", "function": {"name": "Read", "description": "read files", "parameters": {"type": "object"}}},
            {"type": "function", "function": {"name": "Edit", "description": "modify files", "parameters": {"type": "object"}}}
        ]);
        let caps = extract_capabilities(Some(&tools));
        assert_eq!(caps.len(), 3);
        assert_eq!(caps[0].id, "Bash");
        assert_eq!(caps[0].category, Some("terminal".into()));
        assert_eq!(caps[1].id, "Read");
        assert_eq!(caps[1].category, Some("filesystem".into()));
        assert_eq!(caps[2].id, "Edit");
        assert_eq!(caps[2].category, Some("filesystem".into()));
    }

    #[test]
    fn test_extract_capabilities_empty() {
        assert!(extract_capabilities(None).is_empty());
        assert!(extract_capabilities(Some(&serde_json::json!([]))).is_empty());
        assert!(extract_capabilities(Some(&serde_json::json!(null))).is_empty());
    }

    #[test]
    fn test_detect_client_type_workbuddy() {
        let mut headers = HeaderMap::new();
        headers.insert("x-ide-name", "WorkBuddy".parse().unwrap());
        assert_eq!(detect_client_type(&headers, &None), ClientType::WorkBuddy);
    }

    #[test]
    fn test_detect_client_type_trae() {
        let mut headers = HeaderMap::new();
        headers.insert("user-agent", "hertz".parse().unwrap());
        assert_eq!(detect_client_type(&headers, &None), ClientType::Trae);
    }

    #[test]
    fn test_detect_client_type_claude_code() {
        let headers = HeaderMap::new();
        let prompt = Some(
            "x-anthropic-billing-header: cc_version=2.1.241.6c2;\nYou are a Claude agent".into(),
        );
        assert_eq!(
            detect_client_type(&headers, &prompt),
            ClientType::ClaudeCode
        );
    }

    #[test]
    fn test_detect_client_type_unknown() {
        let headers = HeaderMap::new();
        assert_eq!(detect_client_type(&headers, &None), ClientType::Unknown);
    }

    #[test]
    fn test_detect_client_type_codex_and_cursor() {
        let mut headers = HeaderMap::new();
        headers.insert("user-agent", "codex-cli/0.1.0".parse().unwrap());
        assert_eq!(detect_client_type(&headers, &None), ClientType::Codex);

        let mut headers = HeaderMap::new();
        headers.insert("user-agent", "Cursor/0.42.0".parse().unwrap());
        assert_eq!(detect_client_type(&headers, &None), ClientType::Cursor);
    }
}
