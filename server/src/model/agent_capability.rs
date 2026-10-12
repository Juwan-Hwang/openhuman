//! Agent capability model — tools an agent exposes to humans.
//!
//! See: `protocol/internal-model/capability.md` §3
//!
//! Phase 7: Agent Capability & Context Layer.
//!
//! An `AgentCapability` describes a tool that an agent can execute on behalf
//! of the human. OpenHuman **does not execute** the tool — it transports the
//! `tool.invoke` request to the agent and relays the `tool.result` back.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// A single tool/capability that an agent exposes.
///
/// Structurally compatible with OpenAI's `tools` / `functions` format:
/// `id` -> `function.name`, `input_schema` -> `function.parameters`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentCapability {
    /// Unique tool identifier (kebab-case, e.g., `github_create_issue`).
    pub id: String,
    /// Human-readable display name.
    pub name: String,
    /// What this tool does.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// Grouping label (`github`, `terminal`, `browser`, ...).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    /// JSON Schema describing the expected input parameters.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub input_schema: Option<Value>,
    /// JSON Schema describing the output shape.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_schema: Option<Value>,
    /// UI rendering hints for the human client (form fields, widgets, ...).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ui_schema: Option<Value>,
    /// Required permission scopes (e.g., `repo:issues:write`).
    #[serde(default)]
    pub permissions: Vec<String>,
    /// Free-form metadata bag.
    #[serde(default)]
    pub metadata: HashMap<String, Value>,
}

impl AgentCapability {
    /// Convert to an OpenAI-compatible function descriptor.
    ///
    /// Produces the `function` object inside OpenAI's `tools[]` array:
    /// `{ "name", "description", "parameters" }`.
    pub fn to_openai_function(&self) -> Value {
        serde_json::json!({
            "name": self.id,
            "description": self.description.as_deref().unwrap_or(""),
            "parameters": self.input_schema.clone().unwrap_or(Value::Object(Default::default())),
        })
    }
}

/// The full capability manifest published by an agent on connect.
///
/// Sent via the `capability.manifest` event. The server persists this
/// and forwards a `capability.updated` event to connected human clients.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityManifest {
    /// The agent publishing this manifest.
    pub agent_id: String,
    /// All tools the agent exposes.
    pub capabilities: Vec<AgentCapability>,
    /// Optional agent context (runtime metadata).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub context: Option<super::agent_context::AgentContext>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_openai_compat() {
        let cap = AgentCapability {
            id: "github_create_issue".into(),
            name: "Create GitHub Issue".into(),
            description: Some("Creates an issue.".into()),
            category: Some("github".into()),
            input_schema: Some(serde_json::json!({
                "type": "object",
                "properties": {
                    "repo": { "type": "string" },
                    "title": { "type": "string" }
                },
                "required": ["repo", "title"]
            })),
            output_schema: None,
            ui_schema: None,
            permissions: vec!["repo:issues:write".into()],
            metadata: HashMap::new(),
        };

        let func = cap.to_openai_function();
        assert_eq!(func["name"], "github_create_issue");
        assert_eq!(func["description"], "Creates an issue.");
        assert_eq!(func["parameters"]["type"], "object");
    }
}
