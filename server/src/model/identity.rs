//! Identity model — HumanIdentity and AgentIdentity.
//!
//! See: `protocol/internal-model/identity.md`

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Participant type discriminator.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ParticipantType {
    Human,
    Agent,
}

/// A lightweight reference to a participant — used in Conversation and Message.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ParticipantRef {
    pub participant_id: String,
    pub participant_type: ParticipantType,
    /// Optional display name for UI rendering.
    /// Not required for protocol identity — populated for convenience.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
}

impl ParticipantRef {
    pub fn human(id: impl Into<String>) -> Self {
        Self {
            participant_id: id.into(),
            participant_type: ParticipantType::Human,
            display_name: None,
        }
    }

    pub fn agent(id: impl Into<String>) -> Self {
        Self {
            participant_id: id.into(),
            participant_type: ParticipantType::Agent,
            display_name: None,
        }
    }

    /// Create a human participant with a display name.
    pub fn human_named(id: impl Into<String>, name: &str) -> Self {
        Self {
            participant_id: id.into(),
            participant_type: ParticipantType::Human,
            display_name: Some(name.to_string()),
        }
    }

    /// Create an agent participant with a display name.
    pub fn agent_named(id: impl Into<String>, name: &str) -> Self {
        Self {
            participant_id: id.into(),
            participant_type: ParticipantType::Agent,
            display_name: Some(name.to_string()),
        }
    }
}

/// Agent client type — drives keepalive intervals and client-specific behavior.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClientType {
    Codex,
    ClaudeCode,
    Trae,
    Custom,
}

impl ClientType {
    /// SSE keepalive interval in seconds for this client type.
    pub fn keepalive_secs(&self) -> u64 {
        match self {
            ClientType::Codex => 5,
            ClientType::ClaudeCode => 10,
            _ => 15,
        }
    }
}

/// Represents a **real person** exposed as an API endpoint.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HumanIdentity {
    pub id: String,
    pub display_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<HumanStatus>,
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub metadata: HashMap<String, serde_json::Value>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Human presence status — realtime value (future: Redis-backed).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HumanStatus {
    Online,
    Away,
    #[default]
    Offline,
}

/// Represents an **AI agent client** that connects via the OpenAI-compatible API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentIdentity {
    pub id: String,
    pub name: String,
    pub client_type: ClientType,
    pub api_key_id: String,
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub metadata: HashMap<String, serde_json::Value>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// An API key record — links an agent to the human endpoint it can reach.
#[derive(Debug, Clone)]
pub struct ApiKey {
    pub id: String,
    /// The raw key string — **transient, never persisted.**
    ///
    /// Populated only to carry the key through a single request so callers
    /// can log or correlate it. Storage backends must clear this before
    /// writing; `key_hash` is the persisted form.
    pub key: String,
    /// SHA-256 hex of the raw key — the only form ever written to storage
    /// and the only thing authentication queries on.
    ///
    /// `None` only for legacy rows read before the backfill migration runs.
    pub key_hash: Option<String>,
    pub agent_id: String,
    /// The human endpoint this key is bound to.
    pub human_id: String,
    /// Which side of a conversation this key may act on — see [`KeyScope`].
    pub scope: KeyScope,
}

/// Which side of a conversation a key may act on.
///
/// - `Caller`: the OpenAI-compatible ingress (`/v1/chat/completions`,
///   `/v1/replies`, `/v1/models`). This is the key handed to agent software.
/// - `Responder`: the seat that answers — the human's WebSocket (`/ws`),
///   history routes, and the HTTP agent seat (`/v1/seat/*`).
/// - `Both`: legacy behaviour, one key for both sides. Existing keys keep it
///   so nothing breaks on upgrade; new keys should pick a side.
/// - `Revoked`: authenticates nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyScope {
    Caller,
    Responder,
    Both,
    Revoked,
}

impl KeyScope {
    pub fn parse(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "caller" => Self::Caller,
            "responder" => Self::Responder,
            "revoked" => Self::Revoked,
            _ => Self::Both,
        }
    }
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Caller => "caller",
            Self::Responder => "responder",
            Self::Both => "both",
            Self::Revoked => "revoked",
        }
    }
    pub fn may_call(&self) -> bool {
        matches!(self, Self::Caller | Self::Both)
    }
    pub fn may_respond(&self) -> bool {
        matches!(self, Self::Responder | Self::Both)
    }
}

impl ApiKey {
    /// Build a key record from a raw key, computing its SHA-256 digest.
    pub fn new(
        id: impl Into<String>,
        raw_key: &str,
        agent_id: impl Into<String>,
        human_id: impl Into<String>,
    ) -> Self {
        Self {
            id: id.into(),
            key: raw_key.to_string(),
            key_hash: Some(crate::crypto::sha256_hex(raw_key)),
            agent_id: agent_id.into(),
            human_id: human_id.into(),
            scope: KeyScope::Both,
        }
    }

    /// Same key, restricted to one side.
    pub fn with_scope(mut self, scope: KeyScope) -> Self {
        self.scope = scope;
        self
    }

    /// A persisted key record — plaintext stripped, digest retained.
    ///
    /// Storage backends convert via this before writing so that a plaintext
    /// key can never reach the database.
    pub fn persisted(&self) -> Self {
        Self {
            id: self.id.clone(),
            key: String::new(),
            key_hash: self
                .key_hash
                .clone()
                .or_else(|| Some(crate::crypto::sha256_hex(&self.key))),
            agent_id: self.agent_id.clone(),
            human_id: self.human_id.clone(),
            scope: self.scope,
        }
    }

    /// The digest of the supplied raw key — used for lookups.
    pub fn hash_of(raw_key: &str) -> String {
        crate::crypto::sha256_hex(raw_key)
    }
}
