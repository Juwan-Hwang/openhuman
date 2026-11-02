//! In-memory implementation of all repository traits.
//!
//! This is the Phase 3/4/7 storage backend. It uses `tokio::sync::Mutex`
//! for interior mutability and `HashMap` for data.
//! In a future phase, a `PostgresStore` will implement the same traits
//! backed by SQLx + PostgreSQL.

use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use chrono::Utc;
use tokio::sync::mpsc;
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::model::agent_capability::AgentCapability;
use crate::model::agent_context::AgentContext;
use crate::model::conversation::{
    Conversation, ConversationParticipant, ConversationStatus, ConversationType, ParticipantRole,
};
use crate::model::identity::{AgentIdentity, ApiKey, HumanIdentity, HumanStatus, ParticipantRef};
use crate::model::message::{Message, MessageStatus};
use crate::state::AuthPrincipal;
use crate::storage::traits::{
    CapabilityRepository, ContextRepository, ConversationRepository, IdentityRepository,
    MessageRepository, ReplyRegistry, TaskRepository,
};

// ── Internal data ──

#[derive(Default)]
struct MemoryData {
    /// Key: SHA-256 hex of the raw API key → key record.
    ///
    /// Indexed by digest, never by plaintext, so the in-memory store mirrors
    /// the hashed-lookup contract of the Postgres backend.
    api_keys: HashMap<String, ApiKey>,
    agents: HashMap<String, AgentIdentity>,
    humans: HashMap<String, HumanIdentity>,
    /// Key: `{agent_id}:{human_id}` → conversation
    conversations: HashMap<String, Conversation>,
    /// Key: conversation_id → messages
    messages: HashMap<String, Vec<Message>>,
    /// Key: conversation_id → pending reply channels (Vec to support
    /// concurrent SSE connections from the same agent — the last one
    /// is the active turn, earlier ones are stale and ignored).
    pending: HashMap<String, Vec<mpsc::UnboundedSender<String>>>,
    /// Key: agent_id → capabilities
    capabilities: HashMap<String, Vec<AgentCapability>>,
    /// Key: agent_id → context
    contexts: HashMap<String, AgentContext>,
    /// Room sequence allocators: room_id → next room_seq to assign.
    room_counters: HashMap<String, i64>,
    /// Room invites by code hash (plaintext codes never stored).
    room_invites: HashMap<String, crate::storage::traits::RoomInvite>,
    /// Streaming cursors: (room, key, session) → last received seq.
    room_cursors: HashMap<(String, String, String), i64>,
    /// API tasks by id (insertion order tracked by created_at + id).
    tasks: HashMap<String, crate::model::task::TaskRecord>,
    /// Files by id.
    files: HashMap<String, crate::api::files::StoredFile>,
}

// ── MemoryStore ──

/// Thread-safe in-memory store implementing all repository traits.
///
/// Clone is cheap (inner `Arc`). Pass to `AppState` or use directly.
#[derive(Clone)]
pub struct MemoryStore {
    data: Arc<Mutex<MemoryData>>,
}

impl MemoryStore {
    /// Create an empty store.
    pub fn new() -> Self {
        Self {
            data: Arc::new(Mutex::new(MemoryData::default())),
        }
    }

    /// Create a store pre-loaded with demo identities and API keys.
    /// This is synchronous because it constructs the data before
    /// wrapping it in a Mutex — no locking needed.
    pub fn seeded() -> Self {
        let now = Utc::now();

        let human = HumanIdentity {
            id: "hum_demo_alice".to_string(),
            display_name: "Alice Chen".to_string(),
            avatar_url: None,
            status: Some(HumanStatus::Online),
            capabilities: vec![
                "answer_questions".to_string(),
                "review_design".to_string(),
                "provide_feedback".to_string(),
            ],
            metadata: {
                let mut m = HashMap::new();
                m.insert(
                    "timezone".to_string(),
                    serde_json::Value::String("Asia/Shanghai".to_string()),
                );
                m.insert(
                    "title".to_string(),
                    serde_json::Value::String("Senior Engineer".to_string()),
                );
                m
            },
            created_at: now,
            updated_at: now,
        };

        let agent = AgentIdentity {
            id: "agt_demo_codex".to_string(),
            name: "Codex Workspace".to_string(),
            client_type: crate::model::identity::ClientType::Codex,
            api_key_id: "key_demo_001".to_string(),
            capabilities: vec!["coding".to_string(), "analysis".to_string()],
            metadata: HashMap::new(),
            created_at: now,
            updated_at: now,
        };

        const DEMO_RAW_KEY: &str = "ohk_demo_alice_codex";
        let api_key = ApiKey::new(
            "key_demo_001",
            DEMO_RAW_KEY,
            agent.id.clone(),
            human.id.clone(),
        );

        let mut data = MemoryData::default();
        data.humans.insert(human.id.clone(), human);
        data.agents.insert(agent.id.clone(), agent);
        // Index by digest and store the stripped form — the plaintext demo
        // key exists only as the literal above, never as a map value.
        data.api_keys
            .insert(ApiKey::hash_of(DEMO_RAW_KEY), api_key.persisted());

        Self {
            data: Arc::new(Mutex::new(data)),
        }
    }
}

impl Default for MemoryStore {
    fn default() -> Self {
        Self::new()
    }
}

// ── IdentityRepository ──

#[async_trait]
impl IdentityRepository for MemoryStore {
    /// Resolve by SHA-256 digest — the stored map never holds plaintext,
    /// so the digest is the only possible lookup key.
    async fn resolve_principal(&self, raw_key: &str) -> Option<AuthPrincipal> {
        let key_hash = ApiKey::hash_of(raw_key);
        let data = self.data.lock().await;
        let api_key = data.api_keys.get(&key_hash)?;
        let agent = data.agents.get(&api_key.agent_id)?.clone();
        let human = data.humans.get(&api_key.human_id)?.clone();
        Some(AuthPrincipal {
            agent,
            human,
            api_key: ApiKey {
                id: api_key.id.clone(),
                // Transient: carried for this request only, never stored.
                key: raw_key.to_string(),
                key_hash: Some(key_hash),
                agent_id: api_key.agent_id.clone(),
                human_id: api_key.human_id.clone(),
                scope: api_key.scope,
                room_id: api_key.room_id.clone(),
            },
        })
    }

    async fn insert_human(&self, mut human: HumanIdentity) {
        let mut data = self.data.lock().await;
        human.status = Some(HumanStatus::Online);
        data.humans.insert(human.id.clone(), human);
    }

    async fn insert_agent(&self, agent: AgentIdentity) {
        let mut data = self.data.lock().await;
        data.agents.insert(agent.id.clone(), agent);
    }

    /// Store a key indexed by its SHA-256 digest, with plaintext stripped.
    async fn insert_api_key(&self, key: ApiKey) {
        let persisted = key.persisted();
        let key_hash = persisted
            .key_hash
            .clone()
            .unwrap_or_else(|| ApiKey::hash_of(&persisted.key));
        let mut data = self.data.lock().await;
        data.api_keys.insert(key_hash, persisted);
    }

    async fn get_human(&self, id: &str) -> Option<HumanIdentity> {
        let data = self.data.lock().await;
        data.humans.get(id).cloned()
    }

    async fn set_human_status(&self, id: &str, status: HumanStatus) -> bool {
        let mut data = self.data.lock().await;
        match data.humans.get_mut(id) {
            Some(h) => {
                h.status = Some(status);
                h.updated_at = Utc::now();
                true
            }
            None => false,
        }
    }
}

// ── ConversationRepository ──

/// Build the in-memory conversation lookup key.
///
/// ASCII Unit Separator is used as the delimiter because a session key is
/// caller-supplied and may legitimately contain `:`, `/` or spaces — a
/// plain `:` join would let two different scopes collide.
fn scope_key(agent_id: &str, human_id: &str, session_key: &str) -> String {
    format!("{}\u{1f}{}\u{1f}{}", agent_id, human_id, session_key)
}

#[async_trait]
impl ConversationRepository for MemoryStore {
    async fn find_or_create(
        &self,
        agent_id: &str,
        human_id: &str,
        session_key: &str,
        system_prompt: Option<String>,
    ) -> Conversation {
        let mut data = self.data.lock().await;
        // The conversation dimension is (agent, human, session). The session
        // key is what keeps separate chat windows apart — without it every
        // window opened with the same API key shares one transcript.
        let key = scope_key(agent_id, human_id, session_key);

        if let Some(cnv) = data.conversations.get(&key) {
            return cnv.clone();
        }

        let now = Utc::now();
        let conversation = Conversation {
            id: format!("cnv_{}", Uuid::now_v7().simple()),
            conversation_type: ConversationType::AgentHuman,
            participants: vec![
                ConversationParticipant {
                    participant: ParticipantRef::agent(agent_id),
                    joined_at: now,
                    role: Some(ParticipantRole::Initiator),
                    first_visible_seq: None,
                },
                ConversationParticipant {
                    participant: ParticipantRef::human(human_id),
                    joined_at: now,
                    role: Some(ParticipantRole::Responder),
                    first_visible_seq: None,
                },
            ],
            title: None,
            status: ConversationStatus::Active,
            metadata: {
                let mut meta = HashMap::new();
                if let Some(prompt) = system_prompt {
                    meta.insert(
                        "system_prompt".to_string(),
                        serde_json::Value::String(prompt),
                    );
                }
                // Persisted so a restarted/other backend can re-derive the
                // same scope, and so operators can see why two conversations
                // with the same participants are distinct.
                meta.insert(
                    "session_key".to_string(),
                    serde_json::Value::String(session_key.to_string()),
                );
                meta
            },
            created_at: now,
            updated_at: now,
            last_message_at: None,
            deleted_at: None,
        };

        data.conversations.insert(key, conversation.clone());
        data.messages.insert(conversation.id.clone(), Vec::new());
        conversation
    }

    async fn get(&self, id: &str) -> Option<Conversation> {
        let data = self.data.lock().await;
        data.conversations.values().find(|c| c.id == id).cloned()
    }

    async fn get_by_agent(&self, agent_id: &str) -> Option<Conversation> {
        let data = self.data.lock().await;
        data.conversations
            .values()
            .find(|c| c.agent_id() == Some(agent_id))
            .cloned()
    }

    async fn list_for_human(&self, human_id: &str) -> Vec<Conversation> {
        let data = self.data.lock().await;
        data.conversations
            .values()
            .filter(|c| {
                c.deleted_at.is_none()
                    && c.participants
                        .iter()
                        .any(|p| p.participant.participant_id == human_id)
            })
            .cloned()
            .collect()
    }

    async fn soft_delete(&self, id: &str) -> bool {
        let mut data = self.data.lock().await;
        // Keyed by scope, not by id: find the entry whose conversation
        // carries this id. A direct `get_mut(id)` never matches and every
        // delete silently reported "not found".
        match data.conversations.values_mut().find(|c| c.id == id) {
            Some(c) if c.deleted_at.is_none() => {
                c.deleted_at = Some(Utc::now());
                true
            }
            _ => false,
        }
    }

    async fn restore(&self, id: &str) -> bool {
        let mut data = self.data.lock().await;
        match data.conversations.values_mut().find(|c| c.id == id) {
            Some(c) if c.deleted_at.is_some() => {
                c.deleted_at = None;
                true
            }
            _ => false,
        }
    }

    async fn delete_permanent(&self, id: &str) -> bool {
        let mut data = self.data.lock().await;
        data.messages.remove(id);
        let scope = data
            .conversations
            .iter()
            .find(|(_, c)| c.id == id)
            .map(|(k, _)| k.clone());
        match scope {
            Some(k) => data.conversations.remove(&k).is_some(),
            None => false,
        }
    }

    async fn list_deleted_for_human(&self, human_id: &str) -> Vec<Conversation> {
        let data = self.data.lock().await;
        let mut trashed: Vec<Conversation> = data
            .conversations
            .values()
            .filter(|c| {
                c.deleted_at.is_some()
                    && c.participants
                        .iter()
                        .any(|p| p.participant.participant_id == human_id)
            })
            .cloned()
            .collect();
        trashed.sort_by_key(|c| std::cmp::Reverse(c.deleted_at));
        trashed
    }
}

// ── MessageRepository ──

#[async_trait]
impl MessageRepository for MemoryStore {
    async fn insert(&self, message: Message) {
        let mut data = self.data.lock().await;
        data.messages
            .entry(message.conversation_id.clone())
            .or_default()
            .push(message);
    }

    async fn list(&self, conversation_id: &str) -> Vec<Message> {
        let data = self.data.lock().await;
        data.messages
            .get(conversation_id)
            .cloned()
            .unwrap_or_default()
    }

    async fn list_undelivered(&self, human_id: &str) -> Vec<Message> {
        let data = self.data.lock().await;
        let mut out: Vec<Message> = data
            .messages
            .values()
            .flatten()
            .filter(|m| m.status == MessageStatus::Pending && m.sender.participant_id != human_id)
            .cloned()
            .collect();
        out.sort_by_key(|m| m.created_at);
        out
    }

    async fn mark_delivered(&self, message_ids: &[String]) {
        let mut data = self.data.lock().await;
        for messages in data.messages.values_mut() {
            for m in messages.iter_mut() {
                if m.status == MessageStatus::Pending && message_ids.contains(&m.id) {
                    m.status = MessageStatus::Delivered;
                }
            }
        }
    }

    async fn find_tool_call(&self, conversation_id: &str, tool_call_id: &str) -> Option<Message> {
        let data = self.data.lock().await;
        data.messages
            .get(conversation_id)?
            .iter()
            .rev()
            .find(|m| {
                m.metadata.get("tool_call_id").and_then(|v| v.as_str()) == Some(tool_call_id)
                    && m.metadata.contains_key("tool_id")
            })
            .cloned()
    }
}

// ── CapabilityRepository (Phase 7) ──

#[async_trait]
impl CapabilityRepository for MemoryStore {
    async fn set_capabilities(&self, agent_id: &str, capabilities: Vec<AgentCapability>) {
        let mut data = self.data.lock().await;
        data.capabilities.insert(agent_id.to_string(), capabilities);
    }

    async fn get_capabilities(&self, agent_id: &str) -> Vec<AgentCapability> {
        let data = self.data.lock().await;
        data.capabilities.get(agent_id).cloned().unwrap_or_default()
    }

    async fn get_capability(&self, agent_id: &str, tool_id: &str) -> Option<AgentCapability> {
        let data = self.data.lock().await;
        data.capabilities
            .get(agent_id)?
            .iter()
            .find(|c| c.id == tool_id)
            .cloned()
    }

    async fn clear_capabilities(&self, agent_id: &str) {
        let mut data = self.data.lock().await;
        data.capabilities.remove(agent_id);
    }
}

// ── ContextRepository (Phase 7) ──

#[async_trait]
impl ContextRepository for MemoryStore {
    async fn set_context(&self, agent_id: &str, context: AgentContext) {
        let mut data = self.data.lock().await;
        data.contexts.insert(agent_id.to_string(), context);
    }

    async fn get_context(&self, agent_id: &str) -> Option<AgentContext> {
        let data = self.data.lock().await;
        data.contexts.get(agent_id).cloned()
    }
}

// ── ReplyRegistry ──

#[async_trait]
impl ReplyRegistry for MemoryStore {
    async fn register(&self, conversation_id: &str, tx: mpsc::UnboundedSender<String>) {
        let mut data = self.data.lock().await;
        // The newest request on a conversation supersedes any older one: an
        // older one still open is a caller that resubmitted (a retry, or a
        // proxy replaying the request). Dropping its sender ends that
        // handler quietly instead of refusing the new request with 409.
        data.pending.insert(conversation_id.to_string(), vec![tx]);
    }

    async fn remove(&self, conversation_id: &str) {
        let mut data = self.data.lock().await;
        // A superseded handler sees its channel closed and exits without
        // calling this, so removing everything here only ends the turn
        // that actually finished.
        data.pending.remove(conversation_id);
    }

    async fn deliver(&self, conversation_id: &str, text: &str) -> bool {
        let mut data = self.data.lock().await;
        if let Some(channels) = data.pending.get_mut(conversation_id) {
            // Deliver to the LAST registered channel (the active turn).
            // Earlier channels are stale concurrent requests that should
            // have been superseded — we leave them to time out naturally.
            // Drop channels whose request already went away (client
            // disconnected mid-stream), then deliver to the newest live one.
            channels.retain(|tx| !tx.is_closed());
            if let Some(tx) = channels.last() {
                let _ = tx.send(text.to_string());
                return true;
            }
        }
        false
    }

    async fn conversations_with_waiters(&self) -> Vec<String> {
        let data = self.data.lock().await;
        data.pending
            .iter()
            .filter(|(_, channels)| channels.iter().any(|tx| !tx.is_closed()))
            .map(|(id, _)| id.clone())
            .collect()
    }
}

// ── RoomRepository (migration 007) ──
//
// The whole room lives behind the same mutex as everything else, so the
// sequence allocation + append in `room_append` is atomic for free. All of
// it evaporates on restart — that is the documented memory-backend room
// behaviour (design doc §6.9); the server logs a warning at boot.

#[async_trait]
impl crate::storage::traits::RoomRepository for MemoryStore {
    async fn room_create(
        &self,
        room_id: &str,
        title: &str,
        owner: &ParticipantRef,
    ) -> Conversation {
        let mut data = self.data.lock().await;
        let now = Utc::now();
        let room = Conversation {
            id: room_id.to_string(),
            conversation_type: ConversationType::Group,
            participants: vec![ConversationParticipant {
                participant: owner.clone(),
                joined_at: now,
                role: Some(ParticipantRole::Owner),
                first_visible_seq: None,
            }],
            title: Some(title.to_string()),
            status: ConversationStatus::Active,
            metadata: HashMap::new(),
            created_at: now,
            updated_at: now,
            last_message_at: None,
            deleted_at: None,
        };
        data.conversations
            .insert(format!("room:{}", room_id), room.clone());
        data.messages.entry(room_id.to_string()).or_default();
        data.room_counters.insert(room_id.to_string(), 1);
        room
    }

    async fn room_append(&self, mut message: Message) -> Option<Message> {
        let mut data = self.data.lock().await;
        let counter = data
            .room_counters
            .entry(message.conversation_id.clone())
            .or_insert(1);
        let seq = *counter;
        *counter += 1;
        message.room_seq = Some(seq);
        message.status = MessageStatus::Sent;
        let cid = message.conversation_id.clone();
        let created = message.created_at;
        data.messages
            .entry(cid.clone())
            .or_default()
            .push(message.clone());
        if let Some(c) = data.conversations.values_mut().find(|c| c.id == cid) {
            c.last_message_at = Some(created);
            c.updated_at = created;
        }
        Some(message)
    }

    async fn room_next_seq(&self, room_id: &str) -> i64 {
        let data = self.data.lock().await;
        *data.room_counters.get(room_id).unwrap_or(&1)
    }

    async fn room_messages_since(
        &self,
        room_id: &str,
        after_seq: i64,
        min_seq: i64,
        limit: usize,
    ) -> Vec<Message> {
        let data = self.data.lock().await;
        data.messages
            .get(room_id)
            .map(|msgs| {
                msgs.iter()
                    .filter(|m| {
                        m.room_seq
                            .map(|s| s > after_seq && s >= min_seq)
                            .unwrap_or(false)
                    })
                    .take(limit)
                    .cloned()
                    .collect()
            })
            .unwrap_or_default()
    }

    async fn room_add_member(
        &self,
        room_id: &str,
        participant: &ParticipantRef,
        role: ParticipantRole,
        first_visible_seq: Option<i64>,
    ) -> bool {
        let mut data = self.data.lock().await;
        let Some(room) = data.conversations.values_mut().find(|c| c.id == room_id) else {
            return false;
        };
        if let Some(existing) = room
            .participants
            .iter_mut()
            .find(|p| p.participant.participant_id == participant.participant_id)
        {
            existing.role = Some(role);
            existing.first_visible_seq = first_visible_seq;
            return true;
        }
        room.participants.push(ConversationParticipant {
            participant: participant.clone(),
            joined_at: Utc::now(),
            role: Some(role),
            first_visible_seq,
        });
        true
    }

    async fn room_remove_member(&self, room_id: &str, participant_id: &str) -> bool {
        let mut data = self.data.lock().await;
        let Some(room) = data.conversations.values_mut().find(|c| c.id == room_id) else {
            return false;
        };
        let before = room.participants.len();
        room.participants.retain(|p| {
            !(p.participant.participant_id == participant_id
                && p.role != Some(ParticipantRole::Owner))
        });
        room.participants.len() != before
    }

    async fn room_member_role(
        &self,
        room_id: &str,
        participant_id: &str,
    ) -> Option<ParticipantRole> {
        let data = self.data.lock().await;
        data.conversations
            .values()
            .find(|c| c.id == room_id)?
            .participants
            .iter()
            .find(|p| p.participant.participant_id == participant_id)
            .and_then(|p| p.role)
    }

    async fn room_first_visible_seq(&self, room_id: &str, participant_id: &str) -> Option<i64> {
        let data = self.data.lock().await;
        data.conversations
            .values()
            .find(|c| c.id == room_id)?
            .participants
            .iter()
            .find(|p| p.participant.participant_id == participant_id)
            .and_then(|p| p.first_visible_seq)
    }

    async fn room_update_metadata(&self, room_id: &str, patch: serde_json::Value) -> bool {
        let mut data = self.data.lock().await;
        let Some(room) = data
            .conversations
            .values_mut()
            .find(|c| c.id == room_id && c.conversation_type == ConversationType::Group)
        else {
            return false;
        };
        if let serde_json::Value::Object(map) = patch {
            for (k, v) in map {
                room.metadata.insert(k, v);
            }
        }
        room.updated_at = Utc::now();
        true
    }

    async fn room_invite_create(&self, invite: crate::storage::traits::RoomInvite) -> bool {
        let mut data = self.data.lock().await;
        if data.room_invites.contains_key(&invite.code_hash) {
            return false;
        }
        data.room_invites.insert(invite.code_hash.clone(), invite);
        true
    }

    async fn room_invite_get(&self, code_hash: &str) -> Option<crate::storage::traits::RoomInvite> {
        let data = self.data.lock().await;
        data.room_invites.get(code_hash).cloned()
    }

    async fn room_invite_revoke(&self, room_id: &str, code_hash: &str) -> bool {
        let mut data = self.data.lock().await;
        match data.room_invites.get_mut(code_hash) {
            Some(inv) if inv.room_id == room_id && inv.revoked_at.is_none() => {
                inv.revoked_at = Some(Utc::now());
                true
            }
            _ => false,
        }
    }

    async fn room_cursor_get(
        &self,
        room_id: &str,
        api_key_id: &str,
        session_key: &str,
    ) -> Option<i64> {
        let data = self.data.lock().await;
        data.room_cursors
            .get(&(
                room_id.to_string(),
                api_key_id.to_string(),
                session_key.to_string(),
            ))
            .copied()
    }

    async fn room_cursor_set(
        &self,
        room_id: &str,
        api_key_id: &str,
        session_key: &str,
        last_received_seq: i64,
    ) {
        let mut data = self.data.lock().await;
        data.room_cursors.insert(
            (
                room_id.to_string(),
                api_key_id.to_string(),
                session_key.to_string(),
            ),
            last_received_seq,
        );
    }

    async fn room_revoke_keys(&self, room_id: &str) {
        let mut data = self.data.lock().await;
        for key in data.api_keys.values_mut() {
            if key.room_id.as_deref() == Some(room_id) {
                key.scope = crate::model::identity::KeyScope::Revoked;
                key.room_id = None; // mirror postgres: revoke AND unbind
            }
        }
    }

    async fn room_member_count(&self, room_id: &str) -> usize {
        let data = self.data.lock().await;
        data.conversations
            .values()
            .find(|c| c.id == room_id)
            .map(|c| c.participants.len())
            .unwrap_or(0)
    }
}

// ── Task Repository (memory) ──

/// Quota: most task rows kept per owner; the oldest finished go first.
fn tasks_max_per_owner() -> usize {
    std::env::var("OPENHUMAN_TASKS_MAX_PER_OWNER")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(2_000)
}

/// Quota: most task rows kept across all owners.
fn tasks_max_total() -> usize {
    std::env::var("OPENHUMAN_TASKS_MAX_TOTAL")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(20_000)
}

/// Drop the oldest finished rows beyond the cap. Active tasks (queued,
/// running) are never pruned, so a burst of open work can exceed the cap
/// temporarily; it settles as tasks finish.
fn prune_tasks(tasks: &mut HashMap<String, crate::model::task::TaskRecord>, owner: &str) {
    let mut finished: Vec<(i64, String, String)> = tasks
        .values()
        .filter(|t| t.status.finished())
        .map(|t| (t.created_at, t.id.clone(), t.owner.clone()))
        .collect();
    finished.sort();
    let owner_count = tasks.values().filter(|t| t.owner == owner).count();
    let mut over_owner = owner_count.saturating_sub(tasks_max_per_owner());
    let mut over_total = tasks.len().saturating_sub(tasks_max_total());
    for (_, id, row_owner) in finished {
        if over_owner == 0 && over_total == 0 {
            break;
        }
        if row_owner == owner && over_owner > 0 {
            over_owner -= 1;
            tasks.remove(&id);
            continue;
        }
        if over_total > 0 {
            over_total -= 1;
            tasks.remove(&id);
        }
    }
}

#[async_trait]
impl TaskRepository for MemoryStore {
    async fn create_task(&self, task: crate::model::task::TaskRecord) {
        let mut d = self.data.lock().await;
        let owner = task.owner.clone();
        d.tasks.insert(task.id.clone(), task);
        prune_tasks(&mut d.tasks, &owner);
    }

    async fn bind_task_conversation(&self, id: &str, conversation_id: &str) {
        let mut d = self.data.lock().await;
        if let Some(t) = d.tasks.get_mut(id) {
            t.conversation_id = Some(conversation_id.to_string());
            t.updated_at = Utc::now().timestamp();
        }
    }

    async fn finish_task(
        &self,
        id: &str,
        answer: Option<serde_json::Value>,
        error: Option<String>,
    ) {
        let mut d = self.data.lock().await;
        if let Some(t) = d.tasks.get_mut(id) {
            if t.status.finished() {
                return;
            }
            t.status = if error.is_some() {
                crate::model::task::TaskStatus::Failed
            } else {
                crate::model::task::TaskStatus::Completed
            };
            t.answer = answer;
            t.error = error;
            t.updated_at = Utc::now().timestamp();
        }
    }

    async fn fail_in_flight_tasks(&self, reason: &str) -> u64 {
        let mut d = self.data.lock().await;
        let mut n = 0;
        let now = Utc::now().timestamp();
        for t in d.tasks.values_mut() {
            if !t.status.finished() {
                t.status = crate::model::task::TaskStatus::Failed;
                t.error = Some(reason.to_string());
                t.updated_at = now;
                n += 1;
            }
        }
        n
    }

    async fn get_task(&self, owner: &str, id: &str) -> Option<crate::model::task::TaskRecord> {
        let d = self.data.lock().await;
        d.tasks.get(id).filter(|t| t.owner == owner).cloned()
    }

    async fn list_tasks(&self, owner: &str, limit: i64) -> Vec<crate::model::task::TaskRecord> {
        let d = self.data.lock().await;
        let mut v: Vec<_> = d
            .tasks
            .values()
            .filter(|t| t.owner == owner)
            .cloned()
            .collect();
        v.sort_by(|a, b| b.created_at.cmp(&a.created_at).then(b.id.cmp(&a.id)));
        v.truncate(limit.max(0) as usize);
        v
    }
}

// ── File Repository (memory) ──

fn files_max_bytes_per_owner() -> usize {
    std::env::var("OPENHUMAN_FILES_MAX_BYTES_PER_OWNER")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(512 * 1024 * 1024)
}

fn files_max_bytes_total() -> usize {
    std::env::var("OPENHUMAN_FILES_MAX_BYTES_TOTAL")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(2 * 1024 * 1024 * 1024)
}

#[async_trait]
impl crate::storage::traits::FileRepository for MemoryStore {
    async fn put_file(&self, id: &str, file: crate::api::files::StoredFile) {
        let mut d = self.data.lock().await;
        let id = id.to_string();
        let owner = file.owner.clone();
        d.files.insert(id.clone(), file);
        // Byte quotas: evict the oldest files first, whichever purpose.
        let mut by_age: Vec<(i64, String, String, usize)> = d
            .files
            .iter()
            .map(|(fid, f)| (f.created_at, fid.clone(), f.owner.clone(), f.bytes.len()))
            .collect();
        by_age.sort();
        let owner_bytes: usize = d
            .files
            .values()
            .filter(|f| f.owner == owner)
            .map(|f| f.bytes.len())
            .sum();
        let mut over_owner = owner_bytes.saturating_sub(files_max_bytes_per_owner());
        let total_bytes: usize = d.files.values().map(|f| f.bytes.len()).sum();
        let mut over_total = total_bytes.saturating_sub(files_max_bytes_total());
        for (_, fid, row_owner, len) in by_age {
            if over_owner == 0 && over_total == 0 {
                break;
            }
            if row_owner == owner && over_owner > 0 {
                over_owner = over_owner.saturating_sub(len);
                d.files.remove(&fid);
                continue;
            }
            if over_total > 0 {
                over_total = over_total.saturating_sub(len);
                d.files.remove(&fid);
            }
        }
    }

    async fn get_file(&self, id: &str) -> Option<crate::api::files::StoredFile> {
        self.data.lock().await.files.get(id).cloned()
    }

    async fn delete_file(&self, owner: &str, id: &str) -> bool {
        let mut d = self.data.lock().await;
        if d.files.get(id).is_some_and(|f| f.owner == owner) {
            d.files.remove(id);
            true
        } else {
            false
        }
    }

    async fn list_files(&self, owner: &str) -> Vec<(String, crate::api::files::StoredFile)> {
        let d = self.data.lock().await;
        let mut v: Vec<_> = d
            .files
            .iter()
            .filter(|(_, f)| f.owner == owner)
            .map(|(id, f)| (id.clone(), f.clone()))
            .collect();
        v.sort_by_key(|(_, f)| std::cmp::Reverse(f.created_at));
        v
    }

    async fn find_output_by_bytes(&self, bytes: &[u8]) -> Option<(String, i64)> {
        let d = self.data.lock().await;
        d.files
            .iter()
            .find(|(_, f)| f.purpose == "output" && f.bytes == bytes)
            .map(|(id, f)| (id.clone(), f.created_at))
    }
}
