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
    CapabilityRepository, ContextRepository, ConversationRepository, IdentityRepository,
    MessageRepository, ReplyRegistry,
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
            + ContextRepository,
        S: 'static + Send + Sync,
    {
        let store = Arc::new(store);
        Self {
            identity: store.clone(),
            conversation: store.clone(),
            message: store.clone(),
            reply: store.clone(),
            capability: store.clone(),
            context: store,
            connections: ConnectionRegistry::new(),
            async_reply: crate::async_reply::AsyncReplyRegistry::new(),
            outbound: crate::async_reply::OutboundQueue::new(),
            ephemeral: None,
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
        let context: Arc<dyn ContextRepository> = Arc::new(store);
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
        }
    }
}
