//! An API task: one unit of human work behind a non-chat endpoint (an
//! image, a transcript, a batch line...). Persisted so quotas survive
//! restarts and work in flight when the server stops can be failed
//! honestly instead of vanishing.

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TaskStatus {
    /// Created, not yet handed to the seat (queued jobs, batches).
    Queued,
    /// The seat has it (the conversation is open and waiting).
    Running,
    Completed,
    Failed,
}

impl TaskStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Queued => "queued",
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Failed => "failed",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "queued" => Some(Self::Queued),
            "running" => Some(Self::Running),
            "completed" => Some(Self::Completed),
            "failed" => Some(Self::Failed),
            _ => None,
        }
    }

    /// Finished rows are the only ones quota pruning may remove: an
    /// active task must never disappear under its owner.
    pub fn finished(&self) -> bool {
        matches!(self, Self::Completed | Self::Failed)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskRecord {
    pub id: String,
    /// The API key owner's agent id.
    pub owner: String,
    /// The endpoint kind: "images", "audio.speech", "completions", ...
    pub api: String,
    pub status: TaskStatus,
    /// The seat conversation the task rides on, once known.
    pub conversation_id: Option<String>,
    /// What the caller asked for (endpoint-shaped, for retries/audits).
    pub request: Value,
    /// The seat's answer, once delivered.
    pub answer: Option<Value>,
    /// Why it failed, when it did.
    pub error: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}
