//! Group rooms (design doc v3, migration 007).
//!
//! One room = one `type = 'group'` conversation + one ordered log + one
//! member set + room-bound caller keys. This module owns the runtime side:
//! the per-room broadcast hub streams subscribe to, the append-then-
//! broadcast pipeline that is the ONLY way room messages enter the log,
//! and the idle-release timer.
//!
//! Ordering guarantee: `room_append` commits first, everything else
//! (WS fanout, stream signals) happens after, so no subscriber ever sees
//! a message that a crash could lose.

pub mod segmenter;

use std::collections::HashMap;
use std::sync::Arc;

use chrono::Utc;
use serde_json::Value;
use tokio::sync::{broadcast, Mutex};
use tokio::task::AbortHandle;
use uuid::Uuid;

use crate::model::content::ContentBlock;
use crate::model::conversation::{ConversationType, ParticipantRole};
use crate::model::identity::{ParticipantRef, ParticipantType};
use crate::model::message::{Message, MessageStatus, MessageVisibility};
use crate::storage::AppState;
use crate::ws::protocol;

/// Feature flag: room routes are only registered when enabled (default
/// off — flip after the validation matrix passes).
pub fn rooms_enabled() -> bool {
    std::env::var("OPENHUMAN_ROOMS")
        .ok()
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
}

/// Segmented-stream switch (default on); off = plain continuous stream +
/// idle release as the fallback delivery mode.
pub fn segmented_enabled() -> bool {
    std::env::var("OPENHUMAN_ROOM_SEGMENTED")
        .ok()
        .map(|v| !(v == "0" || v.eq_ignore_ascii_case("false")))
        .unwrap_or(true)
}

/// Idle release: seconds of room silence after which the server ends the
/// turn itself. Counts only after the first member message of a turn —
/// nobody spoke means keepalive forever, never an empty turn. `0` disables.
pub fn idle_secs(metadata: &HashMap<String, Value>) -> u64 {
    metadata
        .get("room_idle_secs")
        .and_then(|v| v.as_u64())
        .or_else(|| {
            std::env::var("OPENHUMAN_ROOM_IDLE_SECS")
                .ok()
                .and_then(|v| v.trim().parse::<u64>().ok())
        })
        .unwrap_or(60)
}

/// Deep idle: minutes without any room speech after which segmenting stops
/// and the open segment switches to plain heartbeats (default 10).
pub fn deep_idle_mins(metadata: &HashMap<String, Value>) -> u64 {
    metadata
        .get("room_deep_idle_mins")
        .and_then(|v| v.as_u64())
        .or_else(|| {
            std::env::var("OPENHUMAN_ROOM_DEEP_IDLE_MINS")
                .ok()
                .and_then(|v| v.trim().parse::<u64>().ok())
        })
        .unwrap_or(10)
}

/// Upper bound on one segment's length with no content (default 60s).
pub fn segment_max_secs(metadata: &HashMap<String, Value>) -> u64 {
    metadata
        .get("room_segment_max_secs")
        .and_then(|v| v.as_u64())
        .or_else(|| {
            std::env::var("OPENHUMAN_ROOM_SEGMENT_MAX_SECS")
                .ok()
                .and_then(|v| v.trim().parse::<u64>().ok())
        })
        .unwrap_or(60)
}

/// Quiet period after content flowed that closes a segment (default 3s,
/// on top of the merge window).
pub fn segment_quiet_secs(metadata: &HashMap<String, Value>) -> u64 {
    metadata
        .get("room_segment_quiet_secs")
        .and_then(|v| v.as_u64())
        .or_else(|| {
            std::env::var("OPENHUMAN_ROOM_SEGMENT_QUIET_SECS")
                .ok()
                .and_then(|v| v.trim().parse::<u64>().ok())
        })
        .unwrap_or(3)
}

/// Hard room size cap, owner included.
pub const ROOM_MAX_MEMBERS: usize = 10;

/// Why a turn ended.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndReason {
    /// The room owner sent `end.turn`.
    Owner,
    /// Idle release: the room fell silent after at least one member spoke.
    Idle,
}

/// A signal on a room's live channel — what streams and timers listen to.
#[derive(Debug, Clone)]
pub enum RoomSignal {
    /// A message committed to the room log (carries its `room_seq`).
    Message(Message),
    /// The turn is over: streams finish with `stop`.
    EndTurn { reason: EndReason },
    /// The owner invoked a tool: streams finish with `tool_calls`.
    ToolInvoke {
        invocation_id: String,
        tool_id: String,
        input: Value,
        text: Option<String>,
    },
}

/// Per-room turn state for the idle-release timer.
#[derive(Default)]
struct TurnState {
    /// At least one caller stream is attached and no end.turn has landed.
    open: bool,
    /// A member has spoken this turn — the idle clock only runs then.
    spoke: bool,
    timer: Option<AbortHandle>,
}

/// The room runtime: live signal channels + turn state, one per room.
///
/// This is coordination state, not data — it lives in `AppState` next to
/// the connection registry and survives nothing (rebuilt on boot; streams
/// re-attach from their cursors).
/// Stream registry key: (room, api key, caller session).
type TripleKey = (String, String, String);

#[derive(Clone, Default)]
pub struct RoomHub {
    channels: Arc<Mutex<HashMap<String, broadcast::Sender<RoomSignal>>>>,
    turns: Arc<Mutex<HashMap<String, TurnState>>>,
    /// Live caller streams per (room, key, session): a new request on the
    /// same triple aborts the previous one (§6.7 resubmit-supersedes).
    streams: Arc<Mutex<HashMap<TripleKey, (u64, AbortHandle)>>>,
    /// Consecutive empty segments per triple, driving the 20→40→60s
    /// progressive no-content segment length (§6.3).
    empty_streaks: Arc<Mutex<HashMap<TripleKey, u32>>>,
}

/// Aborts the replaced stream when a newer request on its triple lands,
/// and unregisters itself when dropped at the end of a request.
pub struct StreamGuard {
    hub: RoomHub,
    key: (String, String, String),
    generation: u64,
}

impl Drop for StreamGuard {
    fn drop(&mut self) {
        let hub = self.hub.clone();
        let key = self.key.clone();
        let generation = self.generation;
        tokio::spawn(async move {
            let mut streams = hub.streams.lock().await;
            if streams.get(&key).map(|(g, _)| *g) == Some(generation) {
                streams.remove(&key);
            }
        });
    }
}

impl RoomHub {
    pub fn new() -> Self {
        Self::default()
    }

    /// Subscribe to a room's live signals.
    pub async fn subscribe(&self, room_id: &str) -> broadcast::Receiver<RoomSignal> {
        let mut channels = self.channels.lock().await;
        channels
            .entry(room_id.to_string())
            .or_insert_with(|| broadcast::channel(256).0)
            .subscribe()
    }

    /// Publish a signal to every live subscriber (no-op when none).
    pub async fn publish(&self, room_id: &str, signal: RoomSignal) {
        let channels = self.channels.lock().await;
        if let Some(tx) = channels.get(room_id) {
            // SendError just means no receivers — fine.
            let _ = tx.send(signal);
        }
    }

    /// Mark a turn open (a caller stream attached).
    pub async fn turn_open(&self, room_id: &str) {
        let mut turns = self.turns.lock().await;
        turns.entry(room_id.to_string()).or_default().open = true;
    }

    pub async fn turn_is_open(&self, room_id: &str) -> bool {
        let turns = self.turns.lock().await;
        turns.get(room_id).map(|t| t.open).unwrap_or(false)
    }

    /// A member spoke: start or reset the idle-release clock.
    ///
    /// The timer only ever runs while a turn is open and someone has
    /// spoken — with no speech there is no turn to release, so keepalive
    /// segments just continue (no empty turns, ever).
    pub async fn note_member_speech(&self, room_id: &str, app: &AppState, idle: u64) {
        if idle == 0 {
            return;
        }
        let hub = self.clone();
        let room = room_id.to_string();
        let mut turns = self.turns.lock().await;
        let state = turns.entry(room.clone()).or_default();
        if !state.open {
            return;
        }
        state.spoke = true;
        if let Some(prev) = state.timer.take() {
            prev.abort();
        }
        let app_clone = app.clone();
        let handle = tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(idle)).await;
            hub.end_turn(&room, EndReason::Idle).await;
            // Let waiting streams hear it over the legacy reply channel too,
            // so nothing hangs if a stream missed the hub signal.
            let _ = app_clone.reply.deliver(&room, "__END_TURN__").await;
        });
        state.timer = Some(handle.abort_handle());
    }

    /// End the current turn: cancel the idle clock, reset speech, signal.
    pub async fn end_turn(&self, room_id: &str, reason: EndReason) {
        {
            let mut turns = self.turns.lock().await;
            let state = turns.entry(room_id.to_string()).or_default();
            state.open = false;
            state.spoke = false;
            if let Some(prev) = state.timer.take() {
                prev.abort();
            }
        }
        self.publish(room_id, RoomSignal::EndTurn { reason }).await;
    }

    /// Abort any live stream on this triple — the new request supersedes.
    pub async fn stream_supersede(&self, room_id: &str, key_id: &str, session_key: &str) {
        let key = (
            room_id.to_string(),
            key_id.to_string(),
            session_key.to_string(),
        );
        let mut streams = self.streams.lock().await;
        if let Some((_, prev)) = streams.remove(&key) {
            prev.abort();
        }
    }

    /// Register a pump task as the triple's live stream. Supersede first;
    /// the guard removes the entry on drop only if nobody newer replaced it.
    pub async fn stream_register(
        &self,
        room_id: &str,
        key_id: &str,
        session_key: &str,
        handle: AbortHandle,
    ) -> StreamGuard {
        let key = (
            room_id.to_string(),
            key_id.to_string(),
            session_key.to_string(),
        );
        let generation = {
            use std::sync::atomic::{AtomicU64, Ordering};
            static GEN: AtomicU64 = AtomicU64::new(1);
            GEN.fetch_add(1, Ordering::Relaxed)
        };
        let mut streams = self.streams.lock().await;
        streams.insert(key.clone(), (generation, handle));
        StreamGuard {
            hub: self.clone(),
            key,
            generation,
        }
    }

    /// How many consecutive segments of this triple closed with no content.
    pub async fn segment_empty_streak(
        &self,
        room_id: &str,
        key_id: &str,
        session_key: &str,
    ) -> u32 {
        let streaks = self.empty_streaks.lock().await;
        streaks
            .get(&(
                room_id.to_string(),
                key_id.to_string(),
                session_key.to_string(),
            ))
            .copied()
            .unwrap_or(0)
    }

    /// Record a segment's outcome: content resets the progressive clock,
    /// no content lengthens the next one.
    pub async fn segment_record_outcome(
        &self,
        room_id: &str,
        key_id: &str,
        session_key: &str,
        had_content: bool,
    ) {
        let mut streaks = self.empty_streaks.lock().await;
        let key = (
            room_id.to_string(),
            key_id.to_string(),
            session_key.to_string(),
        );
        if had_content {
            streaks.remove(&key);
        } else {
            *streaks.entry(key).or_insert(0) += 1;
        }
    }

    /// The instant at which the room last saw any message — the deep-idle
    /// clock the segmenter watches. Derived from the log, so it survives
    /// hub restarts.
    pub async fn last_activity(app: &AppState, room_id: &str) -> Option<chrono::DateTime<Utc>> {
        let next = app.room.room_next_seq(room_id).await;
        if next <= 1 {
            return None;
        }
        app.room
            .room_messages_since(room_id, next - 2, 0, 1)
            .await
            .first()
            .map(|m| m.created_at)
    }
}

/// Whether this conversation id is a live room.
pub async fn is_room(app: &AppState, conversation_id: &str) -> bool {
    app.conversation
        .get(conversation_id)
        .await
        .map(|c| c.conversation_type == ConversationType::Group)
        .unwrap_or(false)
}

/// Append a message to the room log and fan it out — the ONLY ingest path.
///
/// Order matters: commit (with its `room_seq`) first, then hub signal,
/// then WS fanout. `sender` is the real speaker — the room path never
/// writes a hardcoded "You".
/// Display name with the short caller-session tag appended (§10.2):
/// "小明的 Claude Code · a3f9" — members can see which stream of the same
/// caller key spoke. Untagged senders keep their plain display name.
pub fn tagged_display_name(
    display: Option<&str>,
    metadata: &HashMap<String, Value>,
) -> Option<String> {
    let base = display?;
    match metadata.get("caller_session").and_then(|v| v.as_str()) {
        Some(tag) => Some(format!("{} · {}", base, tag)),
        None => Some(base.to_string()),
    }
}

pub async fn append_and_broadcast(
    app: &AppState,
    room_id: &str,
    sender: ParticipantRef,
    text: &str,
    mut metadata: HashMap<String, Value>,
) -> Option<Message> {
    let mentions = parse_mentions(app, room_id, text).await;
    if !mentions.is_empty() {
        metadata.insert(
            "mentions".to_string(),
            Value::Array(mentions.into_iter().map(Value::String).collect()),
        );
    }

    let message = Message {
        id: format!("msg_{}", Uuid::now_v7().simple()),
        conversation_id: room_id.to_string(),
        sender: sender.clone(),
        content: ContentBlock::text(text),
        attachments: Vec::new(),
        metadata,
        status: MessageStatus::Sent,
        visibility: MessageVisibility::HumanVisible,
        created_at: Utc::now(),
        room_seq: None,
    };

    let stored = app.room.room_append(message).await?;

    // Streams first (they are latency-critical), then device fanout.
    app.rooms
        .publish(room_id, RoomSignal::Message(stored.clone()))
        .await;

    let sender_type = match stored.sender.participant_type {
        ParticipantType::Human => "human",
        ParticipantType::Agent => "agent",
    };
    let event = protocol::message_received(
        room_id,
        &stored.id,
        &stored.sender.participant_id,
        sender_type,
        tagged_display_name(stored.sender.display_name.as_deref(), &stored.metadata).as_deref(),
        text,
    );
    broadcast_event(app, room_id, &event).await;
    Some(stored)
}

/// Send an event to every current member's devices. Membership is read
/// fresh at send time, so a kicked member stops receiving immediately.
pub async fn broadcast_event(app: &AppState, room_id: &str, event: &crate::model::event::Event) {
    let Some(room) = app.conversation.get(room_id).await else {
        return;
    };
    let json = protocol::event_to_json(event);
    let member_ids: Vec<String> = room
        .participants
        .iter()
        .filter(|p| p.participant.participant_type == ParticipantType::Human)
        .map(|p| p.participant.participant_id.clone())
        .collect();
    app.connections
        .send_to_room(room_id, &member_ids, &json)
        .await;
}

/// Resolve `@名字` mentions to member participant ids. Names come from the
/// human identities of the room's members. Ambiguous names (two members
/// share one) match nobody — @ affects highlight/notify only, never
/// delivery.
async fn parse_mentions(app: &AppState, room_id: &str, text: &str) -> Vec<String> {
    if !text.contains('@') {
        return Vec::new();
    }
    let Some(room) = app.conversation.get(room_id).await else {
        return Vec::new();
    };
    let mut names: HashMap<String, String> = HashMap::new();
    for p in &room.participants {
        if p.participant.participant_type != ParticipantType::Human {
            continue;
        }
        if let Some(h) = app.identity.get_human(&p.participant.participant_id).await {
            match names.entry(h.display_name.clone()) {
                std::collections::hash_map::Entry::Vacant(e) => {
                    e.insert(h.id.clone());
                }
                // Duplicate name: poison the entry so it matches nobody.
                std::collections::hash_map::Entry::Occupied(mut e) => {
                    e.insert(String::new());
                }
            }
        }
    }
    let mut found = Vec::new();
    for (name, pid) in names {
        if pid.is_empty() {
            continue;
        }
        if text.contains(&format!("@{}", name)) {
            found.push(pid);
        }
    }
    found
}

/// A member's role in the room, or `None` when not a member.
pub async fn role_of(
    app: &AppState,
    room_id: &str,
    participant_id: &str,
) -> Option<ParticipantRole> {
    app.room.room_member_role(room_id, participant_id).await
}
