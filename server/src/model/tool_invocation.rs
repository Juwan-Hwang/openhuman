//! Tool invocation model — request/result transport for human→agent tool calls.
//!
//! See: `protocol/internal-model/capability.md` §9
//!
//! Phase 7: Agent Capability & Context Layer.
//!
//! OpenHuman is a **transport layer** for tool invocation. It does not
//! execute tools — it carries `tool.invoke` from the human to the agent
//! and relays `tool.result` back.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Status of a tool invocation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InvocationStatus {
    /// Request sent, awaiting agent response.
    Pending,
    /// Agent executed successfully, result available.
    Success,
    /// Agent execution failed.
    Error,
    /// Human cancelled the request.
    Cancelled,
    /// Agent did not respond within timeout.
    Timeout,
}

/// A `tool.invoke` request — sent by the human, routed to the agent.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolInvoke {
    /// Unique invocation ID (used to correlate request → result).
    pub invocation_id: String,
    /// The tool/capability being invoked.
    pub tool_id: String,
    /// Input parameters conforming to `AgentCapability.input_schema`.
    pub input: Value,
}

/// A `tool.result` response — sent by the agent, routed to the human.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolResult {
    /// Correlates to the original `ToolInvoke.invocation_id`.
    pub invocation_id: String,
    /// The tool that was invoked.
    pub tool_id: String,
    /// Outcome of the invocation.
    pub status: InvocationStatus,
    /// Output data conforming to `AgentCapability.output_schema`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output: Option<Value>,
    /// Error message if `status == Error`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl ToolInvoke {
    /// Create a new tool invocation with a fresh UUIDv7-based ID.
    pub fn new(tool_id: impl Into<String>, input: Value) -> Self {
        Self {
            invocation_id: format!("inv_{}", uuid::Uuid::now_v7().simple()),
            tool_id: tool_id.into(),
            input,
        }
    }
}

impl ToolResult {
    /// Create a successful result.
    pub fn success(
        invocation_id: impl Into<String>,
        tool_id: impl Into<String>,
        output: Value,
    ) -> Self {
        Self {
            invocation_id: invocation_id.into(),
            tool_id: tool_id.into(),
            status: InvocationStatus::Success,
            output: Some(output),
            error: None,
        }
    }

    /// Create an error result.
    pub fn error(
        invocation_id: impl Into<String>,
        tool_id: impl Into<String>,
        error: impl Into<String>,
    ) -> Self {
        Self {
            invocation_id: invocation_id.into(),
            tool_id: tool_id.into(),
            status: InvocationStatus::Error,
            output: None,
            error: Some(error.into()),
        }
    }
}
