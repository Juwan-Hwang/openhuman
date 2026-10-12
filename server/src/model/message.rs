//! Message model — the atomic unit of communication.
//!
//! See: `protocol/internal-model/message.md`

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::content::{Attachment, ContentBlock};
use super::identity::ParticipantRef;

/// Delivery lifecycle of a message.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MessageStatus {
    Pending,
    Sent,
    Delivered,
    Read,
    Failed,
}

/// Visibility of a message in the human-facing UI.
///
/// Messages from the agent's OpenAI `messages[]` array may include
/// `system` prompts and `assistant` context replay that are **not
/// real communication** and should not appear in the human's chat.
///
/// - `HumanVisible` — a genuine message the human should see.
/// - `InternalOnly` — system prompt, context replay, metadata —
///   stored for audit but not shown in the chat timeline.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MessageVisibility {
    #[default]
    HumanVisible,
    InternalOnly,
}

/// A single message in a conversation.
///
/// The model is **role-neutral**: it stores `sender` (a ParticipantRef),
/// not an OpenAI `role`. The `user` / `assistant` mapping happens only
/// at the `openai_compat` boundary.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub conversation_id: String,
    pub sender: ParticipantRef,
    pub content: ContentBlock,
    #[serde(default)]
    pub attachments: Vec<Attachment>,
    #[serde(default)]
    pub metadata: HashMap<String, Value>,
    pub status: MessageStatus,
    /// Whether this message should appear in the human's chat UI.
    /// System prompts and context replay are `InternalOnly`.
    #[serde(default)]
    pub visibility: MessageVisibility,
    pub created_at: DateTime<Utc>,
}
