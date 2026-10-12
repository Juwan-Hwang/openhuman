//! Conversation model.
//!
//! See: `protocol/internal-model/conversation.md`

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::identity::ParticipantRef;

/// Conversation type — who is talking.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConversationType {
    #[serde(rename = "agent_human")]
    AgentHuman,
    #[serde(rename = "human_human")]
    HumanHuman,
}

/// Conversation lifecycle status.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConversationStatus {
    Created,
    Active,
    Archived,
    Closed,
}

/// Participant reference within a conversation — embeds join time and role.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationParticipant {
    #[serde(flatten)]
    pub participant: ParticipantRef,
    pub joined_at: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub role: Option<ParticipantRole>,
}

/// Role of a participant within a conversation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ParticipantRole {
    Initiator,
    Responder,
    Observer,
}

/// A communication context between two or more participants.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: String,
    #[serde(rename = "type")]
    pub conversation_type: ConversationType,
    pub participants: Vec<ConversationParticipant>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// When the conversation was discarded, if it was.
    ///
    /// `None` means live. Set means in the trash: hidden from the default
    /// listing, still holding its messages, restorable.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub deleted_at: Option<DateTime<Utc>>,
    pub status: ConversationStatus,
    #[serde(default)]
    pub metadata: HashMap<String, Value>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_message_at: Option<DateTime<Utc>>,
}

impl Conversation {
    /// Find the human participant's ID in this conversation.
    pub fn human_id(&self) -> Option<&str> {
        self.participants
            .iter()
            .find(|p| p.participant.participant_type == super::identity::ParticipantType::Human)
            .map(|p| p.participant.participant_id.as_str())
    }

    /// Find the agent participant's ID.
    pub fn agent_id(&self) -> Option<&str> {
        self.participants
            .iter()
            .find(|p| p.participant.participant_type == super::identity::ParticipantType::Agent)
            .map(|p| p.participant.participant_id.as_str())
    }
}
