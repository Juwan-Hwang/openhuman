//! Agent context model — non-sensitive runtime metadata about an agent.
//!
//! See: `protocol/internal-model/capability.md` §4
//!
//! Phase 7: Agent Capability & Context Layer.
//!
//! `AgentContext` provides human-facing metadata about the agent's working
//! environment: system prompt in use, model details, runtime platform,
//! repository/branch, etc. It **must never** contain secrets, API tokens,
//! or any sensitive credential.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Non-sensitive runtime context for an agent.
///
/// Stored alongside capabilities and pushed to human clients for
/// display purposes (e.g., "Agent is using GPT-4o on branch `main`").
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentContext {
    /// The agent this context belongs to.
    pub agent_id: String,
    /// The system prompt in use (may be truncated for display).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system_prompt: Option<String>,
    /// Model metadata: `{ name, provider, max_tokens }`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<Value>,
    /// Runtime info: `{ platform, version, session_id }`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub runtime: Option<Value>,
    /// Environment info: `{ repo, branch, working_directory }`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub environment: Option<Value>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_serialize() {
        let ctx = AgentContext {
            agent_id: "agt_demo".into(),
            system_prompt: Some("You are a coding assistant.".into()),
            model: Some(serde_json::json!({ "name": "gpt-4o", "provider": "openai" })),
            runtime: Some(serde_json::json!({ "platform": "linux", "version": "0.1.0" })),
            environment: Some(
                serde_json::json!({ "repo": "openhuman/openhuman", "branch": "main" }),
            ),
        };

        let json = serde_json::to_value(&ctx).unwrap();
        assert_eq!(json["agent_id"], "agt_demo");
        assert_eq!(json["model"]["name"], "gpt-4o");
        assert_eq!(json["environment"]["branch"], "main");
    }
}
