//! Messages kept in memory, not in the database.
//!
//! The caller replays its whole transcript on every request, so the server
//! does not need its own copy: by default a conversation's messages live
//! here, in memory, and are gone after a restart. A conversation the person
//! chooses to keep is written to the persistent store with
//! [`EphemeralMessages::save`] (the console's Save button,
//! `POST /v1/conversations/:id/save`, or the seat's `POST /v1/seat/save`).
//!
//! `OPENHUMAN_PERSIST_MESSAGES=1` restores the old behaviour of writing every
//! message to the database.

use async_trait::async_trait;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::model::message::{Message, MessageStatus};
use crate::storage::traits::{ConversationRepository, MessageRepository};

/// Most messages kept per conversation; older ones fall off.
const PER_CONVERSATION_CAP: usize = 2000;

#[derive(Default)]
struct Inner {
    messages: HashMap<String, Vec<Message>>,
    saved: HashSet<String>,
}

pub struct EphemeralMessages {
    inner: Mutex<Inner>,
    conversations: Arc<dyn ConversationRepository>,
    persistent: Arc<dyn MessageRepository>,
}

/// Whether every message should go to the database (the old behaviour).
pub fn persist_all() -> bool {
    matches!(
        std::env::var("OPENHUMAN_PERSIST_MESSAGES").as_deref(),
        Ok("1") | Ok("true") | Ok("on")
    )
}

impl EphemeralMessages {
    pub fn new(
        conversations: Arc<dyn ConversationRepository>,
        persistent: Arc<dyn MessageRepository>,
    ) -> Self {
        Self {
            inner: Mutex::new(Inner::default()),
            conversations,
            persistent,
        }
    }

    /// Write a conversation's in-memory messages to the persistent store.
    /// Returns how many were newly saved. Saving twice writes nothing twice.
    pub async fn save(&self, conversation_id: &str) -> usize {
        let to_write: Vec<Message> = {
            let mut g = self.inner.lock().await;
            let msgs = g.messages.get(conversation_id).cloned().unwrap_or_default();
            let fresh: Vec<Message> = msgs
                .into_iter()
                .filter(|m| !g.saved.contains(&m.id))
                .collect();
            for m in &fresh {
                g.saved.insert(m.id.clone());
            }
            fresh
        };
        let n = to_write.len();
        for m in to_write {
            self.persistent.insert(m).await;
        }
        n
    }
}

#[async_trait]
impl MessageRepository for EphemeralMessages {
    async fn insert(&self, message: Message) {
        let mut g = self.inner.lock().await;
        let v = g
            .messages
            .entry(message.conversation_id.clone())
            .or_default();
        v.push(message);
        if v.len() > PER_CONVERSATION_CAP {
            let drop = v.len() - PER_CONVERSATION_CAP;
            v.drain(..drop);
        }
    }

    /// In-memory messages, or the saved copy for a conversation that is no
    /// longer in memory (after a restart).
    async fn list(&self, conversation_id: &str) -> Vec<Message> {
        let mem = {
            let g = self.inner.lock().await;
            g.messages.get(conversation_id).cloned().unwrap_or_default()
        };
        if mem.is_empty() {
            self.persistent.list(conversation_id).await
        } else {
            mem
        }
    }

    async fn list_undelivered(&self, human_id: &str) -> Vec<Message> {
        let candidates: Vec<Message> = {
            let g = self.inner.lock().await;
            g.messages
                .values()
                .flatten()
                .filter(|m| {
                    m.status == MessageStatus::Pending && m.sender.participant_id != human_id
                })
                .cloned()
                .collect()
        };
        // Only this human's conversations.
        let mut owned: HashMap<String, bool> = HashMap::new();
        let mut out = Vec::new();
        for m in candidates {
            let mine = match owned.get(&m.conversation_id) {
                Some(b) => *b,
                None => {
                    let b = self
                        .conversations
                        .get(&m.conversation_id)
                        .await
                        .and_then(|c| c.human_id().map(|h| h == human_id))
                        .unwrap_or(false);
                    owned.insert(m.conversation_id.clone(), b);
                    b
                }
            };
            if mine {
                out.push(m);
            }
        }
        out.sort_by_key(|m| m.created_at);
        out
    }

    async fn mark_delivered(&self, message_ids: &[String]) {
        let mut g = self.inner.lock().await;
        for msgs in g.messages.values_mut() {
            for m in msgs.iter_mut() {
                if m.status == MessageStatus::Pending && message_ids.contains(&m.id) {
                    m.status = MessageStatus::Delivered;
                }
            }
        }
    }

    async fn find_tool_call(&self, conversation_id: &str, tool_call_id: &str) -> Option<Message> {
        let g = self.inner.lock().await;
        g.messages
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::content::ContentBlock;
    use crate::model::identity::ParticipantRef;
    use crate::model::message::MessageVisibility;
    use crate::storage::memory::MemoryStore;
    use crate::storage::traits::ConversationRepository;

    fn msg(conv: &str, id: &str) -> Message {
        Message {
            id: id.to_string(),
            conversation_id: conv.to_string(),
            sender: ParticipantRef::agent_named("agt_x", "Agent"),
            content: ContentBlock::text("hi"),
            attachments: Vec::new(),
            metadata: HashMap::new(),
            status: MessageStatus::Pending,
            visibility: MessageVisibility::HumanVisible,
            created_at: chrono::Utc::now(),
        }
    }

    #[tokio::test]
    async fn messages_stay_in_memory_until_saved() {
        let store = Arc::new(MemoryStore::seeded());
        let conv = store.find_or_create("agt_x", "hum_x", "k", None).await;
        let eph = EphemeralMessages::new(store.clone(), store.clone());
        eph.insert(msg(&conv.id, "m1")).await;
        assert!(store.list(&conv.id).await.is_empty(), "nothing written yet");
        assert_eq!(eph.list(&conv.id).await.len(), 1);
        assert_eq!(eph.save(&conv.id).await, 1);
        assert_eq!(eph.save(&conv.id).await, 0, "saving twice writes once");
        assert_eq!(store.list(&conv.id).await.len(), 1);
    }

    #[tokio::test]
    async fn undelivered_is_scoped_to_the_human() {
        let store = Arc::new(MemoryStore::seeded());
        let mine = store.find_or_create("agt_x", "hum_me", "a", None).await;
        let theirs = store.find_or_create("agt_y", "hum_other", "b", None).await;
        let eph = EphemeralMessages::new(store.clone(), store.clone());
        eph.insert(msg(&mine.id, "m1")).await;
        eph.insert(msg(&theirs.id, "m2")).await;
        let got = eph.list_undelivered("hum_me").await;
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].id, "m1");
    }
}
