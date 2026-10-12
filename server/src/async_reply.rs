//! Asynchronous reply mode — for when a human cannot answer within one
//! HTTP request lifetime.
//!
//! # Why this exists
//!
//! The blocking path waits on the human with a fixed 300-second timeout and
//! then answers `504 Gateway Timeout`. That is a poor fit for a human in the
//! loop: people answer on the order of minutes to hours, and a dropped
//! request means the agent loses the turn entirely (and, with it, whatever
//! work was in flight).
//!
//! Asynchronous mode decouples the two halves:
//!
//! ```text
//! agent ──POST /v1/chat/completions──▶ 202 + invocation_id   (returns at once)
//! agent ──GET /v1/replies/{id}───────▶ pending … completed   (long-poll)
//! human ──WS reply.send──────────────▶ completes the invocation
//! ```
//!
//! The blocking path is untouched — async mode is opted into per request, so
//! existing agents keep working exactly as before.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use chrono::{DateTime, Utc};
use tokio::sync::{broadcast, Mutex, RwLock};
use uuid::Uuid;

/// How long a `GET /v1/replies/{id}` long-poll waits before returning
/// `pending` again. Clients are expected to re-poll; this only bounds how
/// long a single request may hang.
pub const DEFAULT_WAIT_SECS: u64 = 30;

/// How long the server lets a turn accumulate before submitting it.
///
/// A human who types and then taps a tool produces two events. Submitting
/// the first immediately means the second can never join it, so the words
/// and the call end up in different responses — the failure mode where
/// "我先看个时间" arrived but the tool call it belonged to did not. Holding
/// briefly lets both land in one assistant message, which is what the
/// protocol allows and what real clients expect.
///
/// Set `OPENHUMAN_MERGE_WINDOW_MS=0` to submit every action immediately.
pub fn merge_window() -> Duration {
    let ms = std::env::var("OPENHUMAN_MERGE_WINDOW_MS")
        .ok()
        .and_then(|v| v.trim().parse::<u64>().ok())
        .unwrap_or(2000);
    Duration::from_millis(ms)
}

/// Upper bound on how long an invocation is remembered.
///
/// An invocation that outlives this is dead: the agent has almost certainly
/// timed out and moved on. Evicting keeps the registry from growing without
/// bound if agents abandon requests (which they do).
pub const INVOCATION_TTL: Duration = Duration::from_secs(24 * 60 * 60);

/// Lifecycle state of an async invocation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AsyncStatus {
    /// Delivered to the human; no reply yet.
    Pending,
    /// The human replied.
    Completed,
    /// The invocation was abandoned or expired.
    Expired,
}

impl AsyncStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Completed => "completed",
            Self::Expired => "expired",
        }
    }
}

/// A single pending async invocation.
struct Invocation {
    conversation_id: String,
    status: AsyncStatus,
    /// Set once the human replies. Retained so a late poll still sees it.
    payload: Option<String>,
    created_at: DateTime<Utc>,
    /// Broadcast on completion so blocked long-polls wake immediately
    /// instead of sitting out their full timeout.
    ready: broadcast::Sender<()>,
}

/// A point-in-time view of an invocation, safe to serialise.
#[derive(Debug, Clone)]
pub struct InvocationSnapshot {
    pub invocation_id: String,
    pub conversation_id: String,
    pub status: AsyncStatus,
    pub payload: Option<String>,
    pub created_at: DateTime<Utc>,
    /// Seconds since creation — surfaced so clients can decide to give up.
    pub age_secs: i64,
}

/// Registry of in-flight async invocations.
///
/// Cloning is cheap: state sits behind `Arc`.
#[derive(Clone, Default)]
pub struct AsyncReplyRegistry {
    inner: Arc<RwLock<HashMap<String, Arc<Mutex<Invocation>>>>>,
    /// Replies awaiting the end of the merge window, keyed by conversation.
    ///
    /// Async turns used to complete the moment the first payload arrived,
    /// so a human who typed and then tapped a tool had the second action
    /// stranded — nothing was waiting to receive it. Staging first lets both
    /// land in one response.
    staging: Arc<RwLock<HashMap<String, Vec<String>>>>,
}

impl AsyncReplyRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Open a new invocation and return its id.
    pub async fn create(&self, conversation_id: &str) -> String {
        let invocation_id = format!("inv_{}", Uuid::now_v7().simple());
        // Capacity 1: the only message ever sent is "wake up". Lagging
        // receivers are fine — they re-check status on wake.
        let (ready, _) = broadcast::channel(1);

        let inv = Arc::new(Mutex::new(Invocation {
            conversation_id: conversation_id.to_string(),
            status: AsyncStatus::Pending,
            payload: None,
            created_at: Utc::now(),
            ready,
        }));

        let mut map = self.inner.write().await;
        Self::evict_locked(&mut map);
        map.insert(invocation_id.clone(), inv);
        invocation_id
    }

    /// Record the human's reply. Returns `false` if the invocation is
    /// unknown or already finished — meaning the caller should fall back to
    /// the synchronous reply channel.
    pub async fn complete(&self, invocation_id: &str, payload: &str) -> bool {
        let inv = {
            let map = self.inner.read().await;
            map.get(invocation_id).cloned()
        };

        let inv = match inv {
            Some(i) => i,
            None => return false,
        };

        let mut inv = inv.lock().await;
        if inv.status != AsyncStatus::Pending {
            return false;
        }
        inv.status = AsyncStatus::Completed;
        inv.payload = Some(payload.to_string());
        // A send error just means nobody is parked on it.
        let _ = inv.ready.send(());
        true
    }

    /// Complete the newest still-pending invocation for a conversation.
    ///
    /// Needed because a human client does not always echo an
    /// `invocation_id` back — most notably when a blocking request timed out
    /// and handed the turn off to async mode after the message had already
    /// been delivered, so the console never learned an id to attach. Without
    /// this, such a reply lands nowhere and the turn is lost.
    ///
    /// Returns `false` when the conversation has no pending invocation.
    /// Hold a reply until the turn's merge window closes, then submit it.
    ///
    /// Async turns previously completed on the first payload, so anything the
    /// human did next had no invocation left to complete and was queued for a
    /// later request. Staging gives the rest of the turn a chance to arrive.
    ///
    /// Returns `true` if an invocation is waiting, so the caller can tell a
    /// staged turn from a reply with nowhere to go.
    pub async fn stage_for_conversation(&self, conversation_id: &str, payload: &str) -> bool {
        if !self.has_pending_for(conversation_id).await {
            return false;
        }

        let is_first = {
            let mut map = self.staging.write().await;
            let entry = map.entry(conversation_id.to_string()).or_default();
            let first = entry.is_empty();
            entry.push(payload.to_string());
            first
        };

        if is_first {
            let reg = self.clone();
            let conv = conversation_id.to_string();
            tokio::spawn(async move {
                tokio::time::sleep(merge_window()).await;
                reg.commit_staged(&conv).await;
            });
        }

        true
    }

    /// Submit everything staged for a conversation as one turn.
    async fn commit_staged(&self, conversation_id: &str) {
        let staged = {
            let mut map = self.staging.write().await;
            map.remove(conversation_id).unwrap_or_default()
        };
        if staged.is_empty() {
            return;
        }

        // A single payload travels as-is; several are wrapped in a JSON
        // array so the parser can see they belong to one turn.
        let payload = if staged.len() == 1 {
            staged[0].clone()
        } else {
            serde_json::to_string(&staged).unwrap_or_else(|_| staged.join("\n\n"))
        };

        self.complete_latest_for_conversation(conversation_id, &payload)
            .await;
    }

    /// Drop staged replies for a conversation, completing nothing.
    ///
    /// Used when the human closes the turn explicitly: the staged content is
    /// committed instead, so nothing is lost.
    pub async fn flush_staged(&self, conversation_id: &str) {
        self.commit_staged(conversation_id).await;
    }

    async fn has_pending_for(&self, conversation_id: &str) -> bool {
        let map = self.inner.read().await;
        for inv in map.values() {
            let guard = match inv.try_lock() {
                Ok(g) => g,
                Err(_) => continue,
            };
            if guard.status == AsyncStatus::Pending && guard.conversation_id == conversation_id {
                return true;
            }
        }
        false
    }

    pub async fn complete_latest_for_conversation(
        &self,
        conversation_id: &str,
        payload: &str,
    ) -> bool {
        let candidate = {
            let map = self.inner.read().await;
            let mut best: Option<(DateTime<Utc>, Arc<Mutex<Invocation>>)> = None;
            for inv in map.values() {
                let created_at = {
                    let guard = match inv.try_lock() {
                        Ok(g) => g,
                        // Busy right now — skip rather than block the scan.
                        Err(_) => continue,
                    };
                    if guard.status != AsyncStatus::Pending
                        || guard.conversation_id != conversation_id
                    {
                        continue;
                    }
                    guard.created_at
                };
                let newer = match &best {
                    Some((t, _)) => created_at > *t,
                    None => true,
                };
                if newer {
                    best = Some((created_at, inv.clone()));
                }
            }
            best.map(|(_, inv)| inv)
        };

        let inv = match candidate {
            Some(i) => i,
            None => return false,
        };

        let mut inv = inv.lock().await;
        // Re-check under the write lock — another task may have completed it
        // between the scan above and here.
        if inv.status != AsyncStatus::Pending {
            return false;
        }
        inv.status = AsyncStatus::Completed;
        inv.payload = Some(payload.to_string());
        let _ = inv.ready.send(());
        true
    }

    /// Current state, or `None` if unknown/evicted.
    pub async fn get(&self, invocation_id: &str) -> Option<InvocationSnapshot> {
        let map = self.inner.read().await;
        let inv = map.get(invocation_id)?;
        let inv = inv.lock().await;
        Some(InvocationSnapshot {
            invocation_id: invocation_id.to_string(),
            conversation_id: inv.conversation_id.clone(),
            status: inv.status,
            payload: inv.payload.clone(),
            created_at: inv.created_at,
            age_secs: (Utc::now() - inv.created_at).num_seconds(),
        })
    }

    /// Long-poll: wait up to `timeout` for the reply.
    ///
    /// Returns the payload if the human answered, `None` if the wait expired
    /// or the invocation is unknown. A caller that gets `None` should poll
    /// again rather than treat it as failure.
    pub async fn wait(&self, invocation_id: &str, timeout: Duration) -> Option<String> {
        // Subscribe before checking, so a completion in between is not lost.
        let (inv, mut rx) = {
            let map = self.inner.read().await;
            let inv = map.get(invocation_id)?.clone();
            let rx = inv.lock().await.ready.subscribe();
            (inv, rx)
        };

        // Fast path: already answered.
        {
            let inv = inv.lock().await;
            if inv.status == AsyncStatus::Completed {
                return inv.payload.clone();
            }
        }

        // Park until woken or the budget runs out.
        if tokio::time::timeout(timeout, rx.recv()).await.is_err() {
            return None;
        }

        let inv = inv.lock().await;
        inv.payload.clone()
    }

    /// Mark an invocation abandoned (agent gave up).
    pub async fn expire(&self, invocation_id: &str) {
        let inv = {
            let map = self.inner.read().await;
            map.get(invocation_id).cloned()
        };
        if let Some(inv) = inv {
            let mut inv = inv.lock().await;
            inv.status = AsyncStatus::Expired;
            let _ = inv.ready.send(());
        }
    }

    /// Drop invocations older than [`INVOCATION_TTL`]. Caller holds the lock.
    fn evict_locked(map: &mut HashMap<String, Arc<Mutex<Invocation>>>) {
        let now = Utc::now();
        map.retain(|_, inv| {
            match inv.try_lock() {
                Ok(inv) => (now - inv.created_at).num_seconds() < INVOCATION_TTL.as_secs() as i64,
                // Busy right now — keep it.
                Err(_) => true,
            }
        });
    }

    /// Number of tracked invocations — exposed for `/health` and tests.
    pub async fn len(&self) -> usize {
        self.inner.read().await.len()
    }

    /// Whether no invocation is tracked.
    pub async fn is_empty(&self) -> bool {
        self.inner.read().await.is_empty()
    }
}

/// Human replies that had nowhere to go at the time they were sent.
///
/// A turn is only reachable while some request is in flight: the reply
/// channel belongs to a suspended SSE/HTTP handler. Once that request ends
/// the channel is gone, so a human who answers afterwards is talking into
/// a void — the words are neither delivered nor retrievable.
///
/// This queue catches them. The next request for the same conversation
/// drains it first, so the reply surfaces on the very next poll/turn
/// instead of never.
///
/// Not durable: a restart drops undelivered replies, same as the reply
/// registry. Persisted message history is the durable record.
#[derive(Clone, Default)]
pub struct OutboundQueue {
    inner: Arc<RwLock<HashMap<String, Vec<String>>>>,
}

impl OutboundQueue {
    pub fn new() -> Self {
        Self::default()
    }

    /// Park an undelivered reply for the next request to collect.
    pub async fn enqueue(&self, conversation_id: &str, payload: &str) {
        let mut map = self.inner.write().await;
        map.entry(conversation_id.to_string())
            .or_default()
            .push(payload.to_string());
    }

    /// Take everything queued for a conversation, oldest first.
    ///
    /// Returns `None` when nothing is waiting, so callers can distinguish
    /// "no backlog" from "empty backlog" without an extra lookup.
    pub async fn drain(&self, conversation_id: &str) -> Option<Vec<String>> {
        let mut map = self.inner.write().await;
        let queued = map.remove(conversation_id)?;
        if queued.is_empty() {
            None
        } else {
            Some(queued)
        }
    }

    /// Number of conversations with a backlog — exposed for tests.
    pub async fn len(&self) -> usize {
        self.inner.read().await.len()
    }

    /// Whether no conversation has a backlog.
    pub async fn is_empty(&self) -> bool {
        self.inner.read().await.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn create_then_complete_roundtrip() {
        let reg = AsyncReplyRegistry::new();
        let id = reg.create("cnv_1").await;

        let snap = reg.get(&id).await.expect("invocation should exist");
        assert_eq!(snap.status, AsyncStatus::Pending);
        assert_eq!(snap.conversation_id, "cnv_1");

        assert!(reg.complete(&id, "hello from human").await);

        let snap = reg.get(&id).await.unwrap();
        assert_eq!(snap.status, AsyncStatus::Completed);
        assert_eq!(snap.payload.as_deref(), Some("hello from human"));
    }

    #[tokio::test]
    async fn completing_unknown_id_is_refused() {
        let reg = AsyncReplyRegistry::new();
        assert!(!reg.complete("inv_nope", "x").await);
        assert!(reg.get("inv_nope").await.is_none());
    }

    #[tokio::test]
    async fn double_complete_is_refused() {
        let reg = AsyncReplyRegistry::new();
        let id = reg.create("cnv_1").await;
        assert!(reg.complete(&id, "first").await);
        assert!(!reg.complete(&id, "second").await, "must not overwrite");
        assert_eq!(
            reg.get(&id).await.unwrap().payload.as_deref(),
            Some("first")
        );
    }

    #[tokio::test]
    async fn wait_wakes_on_completion() {
        let reg = AsyncReplyRegistry::new();
        let id = reg.create("cnv_1").await;

        let waiter = {
            let reg = reg.clone();
            let id = id.clone();
            tokio::spawn(async move { reg.wait(&id, Duration::from_secs(5)).await })
        };

        // Give the waiter a moment to actually park on the channel.
        tokio::time::sleep(Duration::from_millis(50)).await;
        reg.complete(&id, "answered").await;

        let got = tokio::time::timeout(Duration::from_secs(2), waiter)
            .await
            .expect("wait should have been woken")
            .expect("task joined");
        assert_eq!(got.as_deref(), Some("answered"));
    }

    #[tokio::test]
    async fn wait_times_out_when_no_reply() {
        let reg = AsyncReplyRegistry::new();
        let id = reg.create("cnv_1").await;
        let started = std::time::Instant::now();
        assert!(reg.wait(&id, Duration::from_millis(150)).await.is_none());
        assert!(started.elapsed() < Duration::from_secs(2));
    }

    #[tokio::test]
    async fn completes_newest_pending_for_conversation() {
        let reg = AsyncReplyRegistry::new();
        let first = reg.create("cnv_1").await;
        let second = reg.create("cnv_1").await;
        let other = reg.create("cnv_2").await;

        assert!(
            reg.complete_latest_for_conversation("cnv_1", "late reply")
                .await
        );

        // The most recent pending invocation for that conversation wins.
        assert_eq!(
            reg.get(&second).await.unwrap().payload.as_deref(),
            Some("late reply")
        );
        assert_eq!(reg.get(&first).await.unwrap().status, AsyncStatus::Pending);
        // Other conversations are untouched.
        assert_eq!(reg.get(&other).await.unwrap().status, AsyncStatus::Pending);
    }

    #[tokio::test]
    async fn conversation_lookup_ignores_finished_invocations() {
        let reg = AsyncReplyRegistry::new();
        let id = reg.create("cnv_1").await;
        assert!(reg.complete(&id, "done").await);
        assert!(
            !reg.complete_latest_for_conversation("cnv_1", "again").await,
            "an already-completed invocation must not be reused"
        );
    }

    #[tokio::test]
    async fn outbound_queue_parks_and_drains_in_order() {
        let q = OutboundQueue::new();
        assert!(
            q.drain("cnv_1").await.is_none(),
            "empty queue drains to None"
        );

        q.enqueue("cnv_1", "first").await;
        q.enqueue("cnv_1", "second").await;
        q.enqueue("cnv_2", "other").await;
        assert_eq!(q.len().await, 2);

        assert_eq!(
            q.drain("cnv_1").await,
            Some(vec!["first".to_string(), "second".to_string()])
        );
        // Drained: a second drain finds nothing, so a reply is delivered once.
        assert!(q.drain("cnv_1").await.is_none());
        // Other conversations are untouched.
        assert_eq!(q.drain("cnv_2").await, Some(vec!["other".to_string()]));
    }

    #[tokio::test]
    async fn only_undelivered_messages_are_drained() {
        // Replaying everything on every reconnect made already-answered
        // messages appear again, and the burst swamped the connection.
        use crate::storage::traits::MessageRepository;

        let store: std::sync::Arc<dyn MessageRepository> =
            std::sync::Arc::new(crate::storage::memory::MemoryStore::new());
        let human = "hum_1";

        let fresh = crate::model::message::Message {
            id: "msg_new".to_string(),
            conversation_id: "cnv_1".to_string(),
            sender: crate::model::identity::ParticipantRef::agent_named("agt_1", "Agent"),
            content: crate::model::content::ContentBlock::text("new"),
            attachments: Vec::new(),
            metadata: std::collections::HashMap::new(),
            status: crate::model::message::MessageStatus::Pending,
            visibility: crate::model::message::MessageVisibility::HumanVisible,
            created_at: chrono::Utc::now(),
        };
        store.insert(fresh.clone()).await;

        let mut old = fresh.clone();
        old.id = "msg_old".to_string();
        old.status = crate::model::message::MessageStatus::Delivered;
        store.insert(old).await;

        let backlog = store.list_undelivered(human).await;
        assert_eq!(backlog.len(), 1, "only the undelivered one comes back");
        assert_eq!(backlog[0].id, "msg_new");

        // After being pushed, it is no longer pending, so a reconnect gets
        // nothing rather than the whole history again.
        store.mark_delivered(&["msg_new".to_string()]).await;
        assert!(store.list_undelivered(human).await.is_empty());
    }

    #[tokio::test]
    async fn staged_turn_merges_instead_of_completing_early() {
        // Completing on the first payload stranded whatever the human did
        // next; staging keeps the turn open for it.
        let reg = AsyncReplyRegistry::new();
        let id = reg.create("cnv_1").await;

        assert!(reg.stage_for_conversation("cnv_1", "我先看个时间").await);
        // Still pending — the window has not closed.
        assert_eq!(reg.get(&id).await.unwrap().status, AsyncStatus::Pending);

        let second =
            r#"{"type":"tool.invoke","invocation_id":"inv_x","tool_id":"probe_ping","input":{}}"#;
        assert!(reg.stage_for_conversation("cnv_1", second).await);

        reg.commit_staged("cnv_1").await;

        let payload = reg.get(&id).await.unwrap().payload.clone().unwrap();
        assert_eq!(reg.get(&id).await.unwrap().status, AsyncStatus::Completed);
        // Both halves travel together, as a JSON array.
        let parsed: serde_json::Value = serde_json::from_str(&payload).unwrap();
        let items = parsed.as_array().expect("merged turn is an array");
        assert_eq!(items.len(), 2, "prose and tool call both present");
    }

    #[tokio::test]
    async fn staging_reports_when_nothing_is_waiting() {
        let reg = AsyncReplyRegistry::new();
        assert!(
            !reg.stage_for_conversation("nobody", "hi").await,
            "a reply with no invocation to answer is not staged"
        );
    }

    #[tokio::test]
    async fn ids_are_unique() {
        let reg = AsyncReplyRegistry::new();
        let a = reg.create("cnv_1").await;
        let b = reg.create("cnv_1").await;
        assert_ne!(a, b, "two turns in one conversation need distinct ids");
        assert_eq!(reg.len().await, 2);
    }
}
