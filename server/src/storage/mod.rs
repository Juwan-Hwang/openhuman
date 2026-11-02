//! Storage abstraction layer.
//!
//! Architecture:
//!
//! ```text
//!   API Layer (auth, openai, mock, ws)
//!        |
//!   AppState (holds trait objects + ConnectionRegistry)
//!        |
//!   ┌──────────────────────────────────┐
//!   │ Repository Traits (data)         │
//!   │   IdentityRepository              │
//!   │   ConversationRepository         │
//!   │   MessageRepository               │
//!   │   CapabilityRepository  (Ph7)     │
//!   │   ContextRepository     (Ph7)     │
//!   │   ReplyRegistry (ephemeral)       │
//!   ├──────────────────────────────────┤
//!   │ ConnectionRegistry (realtime)     │
//!   │   human_id → [device_id → tx]    │
//!   └──────────────────────────────────┘
//! ```
//!
//! `AppState` is the single shared state passed to Axum handlers.
//! It holds `Arc<dyn Repository>` trait objects + `ConnectionRegistry`,
//! so handlers never know whether they're talking to memory or PostgreSQL.

pub mod ephemeral;
pub mod memory;
pub mod postgres;
pub mod traits;

use std::sync::Arc;

use crate::storage::traits::{
    CapabilityRepository, ContextRepository, ConversationRepository, FileRepository,
    IdentityRepository, MessageRepository, ReplyRegistry, RoomRepository, TaskRepository,
    VectorStoreRepository,
};
use crate::ws::registry::ConnectionRegistry;

/// The application state shared across all Axum handlers.
///
/// Each field is a trait object (or `Arc`), so the concrete implementation
/// (Memory, PostgreSQL, etc.) can be swapped without touching handler code.
#[derive(Clone)]
pub struct AppState {
    pub identity: Arc<dyn IdentityRepository>,
    pub conversation: Arc<dyn ConversationRepository>,
    pub message: Arc<dyn MessageRepository>,
    pub reply: Arc<dyn ReplyRegistry>,
    /// Agent capability storage — tools an agent exposes to humans.
    pub capability: Arc<dyn CapabilityRepository>,
    /// Agent context storage — non-sensitive runtime metadata.
    pub context: Arc<dyn ContextRepository>,
    /// Realtime WebSocket connection registry — manages online human devices.
    pub connections: ConnectionRegistry,
    /// In-flight asynchronous invocations — see [`crate::async_reply`].
    ///
    /// Held outside the storage traits because it is purely ephemeral
    /// coordination state, not persisted data.
    pub async_reply: crate::async_reply::AsyncReplyRegistry,
    /// Human replies with no request to carry them — see
    /// [`crate::async_reply::OutboundQueue`]. Drained by the next request
    /// for the same conversation.
    pub outbound: crate::async_reply::OutboundQueue,
    /// The in-memory message store when messages are not persisted (the
    /// default with PostgreSQL); `None` when every message is already in
    /// the database or the whole backend is in memory.
    pub ephemeral: Option<Arc<ephemeral::EphemeralMessages>>,
    /// The model name callers see in `/v1/models` — see [`ModelName`].
    pub model: Arc<ModelName>,
    /// Group-room storage (migration 007). Same backend as the rest;
    /// with the memory backend every room evaporates on restart.
    pub room: Arc<dyn RoomRepository>,
    /// API-task storage (migration 008). Persistent with the postgres
    /// backend; with memory, a restart forgets tasks — but they are
    /// failed at boot either way (see `fail_in_flight_tasks`).
    pub task: Arc<dyn TaskRepository>,
    /// Files API storage (migration 009). Byte quotas are enforced by
    /// the repository on every write.
    pub file: Arc<dyn FileRepository>,
    /// Vector store storage (migration 010). Per-owner caps are enforced
    /// by the repository on every write.
    pub vector: Arc<dyn VectorStoreRepository>,
    /// Room runtime: live signal channels + idle-release timers.
    pub rooms: crate::rooms::RoomHub,
}

/// The name this instance answers to as a "model".
///
/// Priority: a name the user pinned (
/// `OPENHUMAN_MODEL`) beats everything and locks the name; otherwise the
/// seat may choose its own name (`oh-seat name …`); until either happens
/// the neutral default `openhuman` is served.
pub struct ModelName {
    name: std::sync::RwLock<String>,
    locked: std::sync::RwLock<bool>,
}

impl ModelName {
    /// From the environment: `OPENHUMAN_MODEL` counts as user-pinned.
    pub fn from_env() -> Self {
        match std::env::var("OPENHUMAN_MODEL") {
            Ok(v) if is_valid_model_name(v.trim()) => Self {
                name: std::sync::RwLock::new(v.trim().to_string()),
                locked: std::sync::RwLock::new(true),
            },
            _ => Self {
                name: std::sync::RwLock::new("openhuman-human".to_string()),
                locked: std::sync::RwLock::new(false),
            },
        }
    }

    pub fn get(&self) -> String {
        self.name.read().unwrap().clone()
    }

    pub fn is_locked(&self) -> bool {
        *self.locked.read().unwrap()
    }

    /// Pin a user-chosen name (wins over the seat's, and locks).
    pub fn set_user(&self, name: &str) {
        *self.name.write().unwrap() = name.to_string();
        *self.locked.write().unwrap() = true;
    }

    /// Set the seat's own chosen name. Fails when the user pinned one.
    pub fn set_seat(&self, name: &str) -> Result<(), SeatNameError> {
        if !is_valid_model_name(name) {
            return Err(SeatNameError::Invalid);
        }
        if self.is_locked() {
            return Err(SeatNameError::Locked);
        }
        *self.name.write().unwrap() = name.to_string();
        Ok(())
    }
}

#[derive(Debug)]
pub enum SeatNameError {
    /// Not a usable model id (empty, too long, or has whitespace/control).
    Invalid,
    /// The user pinned a model name; the seat cannot override it.
    Locked,
}

/// A usable model id: 1–64 chars, no whitespace or control characters.
pub fn is_valid_model_name(name: &str) -> bool {
    !name.is_empty()
        && name.chars().count() <= 64
        && name.chars().all(|c| !c.is_whitespace() && !c.is_control())
}

impl AppState {
    /// Build an `AppState` from a single store that implements all traits.
    ///
    /// `MemoryStore` satisfies this — it implements all six traits in one type.
    pub fn from_store<S>(store: S) -> Self
    where
        S: IdentityRepository
            + ConversationRepository
            + MessageRepository
            + ReplyRegistry
            + CapabilityRepository
            + ContextRepository
            + RoomRepository
            + TaskRepository
            + FileRepository
            + VectorStoreRepository,
        S: 'static + Send + Sync,
    {
        let store = Arc::new(store);
        Self {
            identity: store.clone(),
            conversation: store.clone(),
            message: store.clone(),
            reply: store.clone(),
            capability: store.clone(),
            context: store.clone(),
            connections: ConnectionRegistry::new(),
            async_reply: crate::async_reply::AsyncReplyRegistry::new(),
            outbound: crate::async_reply::OutboundQueue::new(),
            ephemeral: None,
            model: Arc::new(ModelName::from_env()),
            task: store.clone(),
            file: store.clone(),
            vector: store.clone(),
            room: store,
            rooms: crate::rooms::RoomHub::new(),
        }
    }

    /// Build an `AppState` from a `PostgresStore` (identity/conversation/message/
    /// capability/context) paired with an `InMemoryReplyRegistry` (reply channels).
    pub fn from_postgres(
        store: postgres::PostgresStore,
        reply: postgres::InMemoryReplyRegistry,
    ) -> Self {
        let identity: Arc<dyn IdentityRepository> = Arc::new(store.clone());
        let conversation: Arc<dyn ConversationRepository> = Arc::new(store.clone());
        let persistent: Arc<dyn MessageRepository> = Arc::new(store.clone());
        // Messages stay in memory unless asked otherwise: the caller's
        // transcript is the record, and a conversation worth keeping is
        // saved explicitly (see `ephemeral`).
        let (message, ephemeral): (Arc<dyn MessageRepository>, _) = if ephemeral::persist_all() {
            (persistent, None)
        } else {
            let eph = Arc::new(ephemeral::EphemeralMessages::new(
                conversation.clone(),
                persistent,
            ));
            (eph.clone() as Arc<dyn MessageRepository>, Some(eph))
        };
        let capability: Arc<dyn CapabilityRepository> = Arc::new(store.clone());
        let context: Arc<dyn ContextRepository> = Arc::new(store.clone());
        let task: Arc<dyn TaskRepository> = Arc::new(store.clone());
        let file: Arc<dyn FileRepository> = Arc::new(store.clone());
        let vector: Arc<dyn VectorStoreRepository> = Arc::new(store.clone());
        let room: Arc<dyn RoomRepository> = Arc::new(store);
        let reply: Arc<dyn ReplyRegistry> = Arc::new(reply);
        Self {
            identity,
            conversation,
            message,
            reply,
            capability,
            context,
            connections: ConnectionRegistry::new(),
            async_reply: crate::async_reply::AsyncReplyRegistry::new(),
            outbound: crate::async_reply::OutboundQueue::new(),
            ephemeral,
            model: Arc::new(ModelName::from_env()),
            task,
            file,
            vector,
            room,
            rooms: crate::rooms::RoomHub::new(),
        }
    }
}
