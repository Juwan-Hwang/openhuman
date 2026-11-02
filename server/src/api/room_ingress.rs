//! Room caller ingress (design doc §5.2, §6) — the `/rooms/:id/v1/*` side.
//!
//! A request here does NOT find-or-create a conversation: the room IS the
//! conversation. New caller speech enters the room log through the single
//! ingest point; the response streams the room log from the caller's
//! cursor, first the backlog then live, closing each segment with a
//! keepalive tool call (segmented mode) or running until end.turn /
//! idle release (fallback mode).

use std::collections::HashMap;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::sse::{Event as SseEvent, Sse};
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::Utc;
use serde_json::{json, Value};
use tokio::sync::mpsc;
use uuid::Uuid;

use super::openai::{
    handle_meta_request, heartbeat_event, is_auxiliary_request, process_inbound_messages,
    resolve_session_key, sse_heartbeat_secs,
};
use crate::model::conversation::ConversationType;
use crate::model::identity::ParticipantRef;
use crate::model::message::Message;
use crate::openai_compat::{ChatCompletionChunk, ChatCompletionRequest};
use crate::profile::AgentProfile;
use crate::rooms::{segmenter, RoomSignal};
use crate::state::AuthPrincipal;
use crate::storage::AppState;

fn err(status: StatusCode, code: &str, message: &str) -> Response {
    (
        status,
        Json(json!({"error": {"message": message, "type": "invalid_request_error", "code": code}})),
    )
        .into_response()
}

/// Clients configured (by fingerprint) for the fallback delivery mode:
/// plain continuous stream + idle release, no keepalive segmentation.
/// Config, not a code branch (§6.0).
fn unsegmented_clients() -> Vec<String> {
    std::env::var("OPENHUMAN_ROOM_UNSEGMENTED_CLIENTS")
        .unwrap_or_default()
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

/// Tool names the request declared — the keepalive whitelist picks from
/// these, never a tool the client does not know.
fn declared_tool_names(req: &ChatCompletionRequest) -> Vec<String> {
    req.tools
        .as_ref()
        .and_then(|t| t.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|t| {
                    t.get("function")
                        .and_then(|f| f.get("name"))
                        .and_then(|n| n.as_str())
                        .map(|s| s.to_string())
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Short per-session tag for UI attribution (§10.2): the first 4 hex of
/// the session key's digest.
fn session_tag(session_key: &str) -> String {
    crate::crypto::sha256_hex(session_key)[..4].to_string()
}

/// POST /rooms/:room_id/v1/chat/completions
pub async fn room_chat_completions(
    State(app): State<AppState>,
    Path(room_id): Path<String>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Json(req): Json<ChatCompletionRequest>,
) -> Response {
    // The room is the conversation.
    let room = match app.conversation.get(&room_id).await {
        Some(c) if c.conversation_type == ConversationType::Group => c,
        _ => return err(StatusCode::NOT_FOUND, "room_not_found", "No such room."),
    };

    // §7.1: auxiliary requests (titles, suggestions) are answered locally.
    // They never touch the log, the cursor, or a subscription.
    let agent_purpose = headers
        .get("x-agent-purpose")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("conversation");
    if agent_purpose != "conversation" {
        return handle_meta_request(req, agent_purpose);
    }
    if is_auxiliary_request(&req) {
        return handle_meta_request(req, "auxiliary");
    }

    let profile = AgentProfile::extract(&headers, &req, &principal.agent.id);
    let session_key = resolve_session_key(&headers, &req, None, false);
    let key_id = principal.api_key.id.clone();
    let tag = session_tag(&session_key);

    // Cursor: a new (room, key, session) triple starts at the current tip —
    // no history dump for new windows/subagents (§6.7).
    let next_seq = app.room.room_next_seq(&room_id).await;
    let cursor = match app
        .room
        .room_cursor_get(&room_id, &key_id, &session_key)
        .await
    {
        Some(c) => c,
        None => {
            let c = next_seq - 1;
            app.room
                .room_cursor_set(&room_id, &key_id, &session_key, c)
                .await;
            c
        }
    };

    // ── Ingest: only content newer than the last segment counts (§6.1.2) ──
    let (_system_prompt, mut inbound) =
        process_inbound_messages(&req, &principal, "pending", &profile.client_type);

    let mut speech: Vec<Message> = Vec::new();
    inbound.retain_mut(|msg| {
        let is_tool = msg.metadata.get("openai_role").and_then(|v| v.as_str()) == Some("tool");
        let call_id = msg
            .metadata
            .get("tool_call_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if is_tool {
            // Keepalive results: by ohka_ prefix, or by pairing when the
            // client rewrote the id (whitelisted/fallback tool + {} args
            // + not an owner invoke — owner invokes carry invocation ids
            // that never match these names with empty args).
            let echo_tool = msg
                .metadata
                .get("echo_tool")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let echo_args = msg
                .metadata
                .get("echo_args")
                .cloned()
                .unwrap_or(Value::Null);
            if segmenter::is_keepalive_call_id(call_id)
                || segmenter::looks_like_keepalive_pair(echo_tool, &echo_args)
            {
                return false;
            }
            let key = if call_id.is_empty() {
                None
            } else {
                Some(call_id)
            };
            let content = msg.content.as_text().unwrap_or("");
            if !crate::session::first_result(&room_id, key, content) {
                return false;
            }
        } else {
            // Interjections arrive with a client lead-in — strip it (§6.4).
            let raw = msg.content.as_text().unwrap_or("").to_string();
            let stripped = segmenter::strip_interjection_leadin(&raw)
                .trim()
                .to_string();
            if stripped.is_empty() {
                return false;
            }
            let images = msg
                .metadata
                .get("images")
                .map(|v| v.to_string())
                .unwrap_or_default();
            // Resend-dedup per (room, caller session): clients resend the
            // full window every turn, so the fingerprint is the stripped
            // text itself — the message count would defeat it. A genuine
            // repeat after the turn was answered passes, because
            // turn_answered clears the seen set.
            let dedup_key = format!("{}\u{1f}{}", room_id, tag);
            let stripped = crate::session::room_resend_tail(&dedup_key, &stripped);
            let fingerprint = format!("user:{}:{}", stripped, images);
            if !crate::session::first_user_turn(&dedup_key, &fingerprint) {
                return false;
            }
            crate::session::room_speech_logged(&dedup_key, &stripped);
            msg.content = crate::model::content::ContentBlock::text(&stripped);
        }
        msg.conversation_id = room_id.clone();
        true
    });
    speech.append(&mut inbound);

    let display = principal.agent.name.clone();
    // NOTE: the cursor is NOT advanced past our own speech here. Member
    // speech that lands between the cursor read and these appends must
    // still stream from the backlog; the pump filters our own lines by
    // their caller_session tag instead (review: the old cursor.max jump
    // silently dropped that window).
    for mut msg in speech {
        // Tool results are room messages too, 60k middle-truncated (§7.4).
        let is_tool = msg.metadata.get("openai_role").and_then(|v| v.as_str()) == Some("tool");
        let text = msg.content.as_text().unwrap_or("").to_string();
        let text = if is_tool {
            let (t, cut) = crate::seat::truncate_middle(&text, crate::seat::COMPACT_OUTPUT_CHARS);
            if cut {
                t
            } else {
                text
            }
        } else {
            text
        };
        msg.metadata
            .insert("caller_session".to_string(), Value::String(tag.clone()));
        let sender = ParticipantRef::agent_named(&principal.agent.id, &display);
        crate::rooms::append_and_broadcast(&app, &room_id, sender, &text, msg.metadata).await;
    }
    // Caller speech counts as room speech for idle purposes only via members;
    // but it must reset a running segment's quiet clock — handled because
    // append broadcasts through the hub, which this stream also follows.

    // Attaching a request opens the room turn.
    app.rooms.turn_open(&room_id).await;

    let meta = room.metadata.clone();
    let segmented = crate::rooms::segmented_enabled()
        && meta
            .get("room_segmented")
            .and_then(|v| v.as_bool())
            .unwrap_or(true)
        && !unsegmented_clients()
            .iter()
            .any(|c| *c == profile.client_type.to_string());

    let stream_flag = req.stream;
    let include_usage = req
        .stream_options
        .as_ref()
        .and_then(|o| o.get("include_usage"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let model_name = room.title.clone().unwrap_or_else(|| room_id.clone());
    let keepalive_secs = match profile.client_type {
        crate::profile::ClientType::Codex => 5,
        crate::profile::ClientType::ClaudeCode => 10,
        _ => 15,
    }
    .max(1)
    .min(sse_heartbeat_secs());
    let tools = declared_tool_names(&req);

    // ── The segment pump: backlog, then live follow ──
    // Supersede: a new request on the same triple replaces the old stream
    // (§6.7) — aborting the old pump closes its channel, ending that SSE.
    app.rooms
        .stream_supersede(&room_id, &key_id, &session_key)
        .await;

    let (tx, mut rx) = mpsc::unbounded_channel::<PumpEvent>();
    let pump_task = {
        let app = app.clone();
        let room_id = room_id.clone();
        let key_id = key_id.clone();
        let session_key = session_key.clone();
        let agent_id = principal.agent.id.clone();
        let tools = tools.clone();
        tokio::spawn(async move {
            pump(PumpCtx {
                app,
                room_id,
                key_id,
                session_key,
                session_tag: tag,
                agent_id,
                cursor,
                meta,
                segmented,
                tools,
                tx,
            })
            .await;
        })
    };
    let guard = app
        .rooms
        .stream_register(
            &room_id,
            &key_id,
            &session_key,
            pump_task.abort_handle(),
            tools,
            &principal.agent.name,
            &session_tag(&session_key),
        )
        .await;

    if stream_flag {
        let completion_id = format!("chatcmpl-{}", Uuid::now_v7().simple());
        let cid = completion_id.clone();
        let mdl = model_name.clone();
        let stream = async_stream::stream! {
            // Lives until the SSE stream ends; only then is the triple's
            // registration released (a superseding request replaces it).
            let _guard = guard;
            let role_chunk = ChatCompletionChunk::role_header(&cid, &mdl);
            yield Ok::<SseEvent, std::convert::Infallible>(
                SseEvent::default().data(serde_json::to_string(&role_chunk).unwrap())
            );
            let mut keepalive = tokio::time::interval(Duration::from_secs(keepalive_secs));
            keepalive.tick().await;
            loop {
                let ev = tokio::select! {
                    _ = keepalive.tick() => {
                        yield Ok::<SseEvent, std::convert::Infallible>(heartbeat_event(&cid, &mdl));
                        continue;
                    }
                    ev = rx.recv() => match ev {
                        Some(e) => e,
                        None => break,
                    },
                };
                match ev {
                    PumpEvent::Text(text) => {
                        for word in text.split_inclusive(char::is_whitespace) {
                            let chunk = ChatCompletionChunk::content_delta(&cid, word, &mdl);
                            yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                        }
                    }
                    PumpEvent::CloseStop => {
                        let chunk = ChatCompletionChunk::finish(&cid, &mdl);
                        yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                        if include_usage {
                            let usage = crate::openai_compat::Usage {
                                prompt_tokens: 0,
                                completion_tokens: 0,
                                total_tokens: 0,
                            };
                            let chunk = ChatCompletionChunk::usage_chunk_with(&cid, usage, &mdl);
                            yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                        }
                        yield Ok(SseEvent::default().data("[DONE]"));
                        break;
                    }
                    PumpEvent::CloseToolCall { id, name, args } => {
                        let chunk = ChatCompletionChunk::tool_call_delta_at(&cid, 0, &id, &name, &args.to_string(), &mdl);
                        yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                        let chunk = ChatCompletionChunk::finish_tool_calls(&cid, &mdl);
                        yield Ok(SseEvent::default().data(serde_json::to_string(&chunk).unwrap()));
                        yield Ok(SseEvent::default().data("[DONE]"));
                        break;
                    }
                }
            }
        };
        return Sse::new(stream).into_response();
    }

    // Async mode: 202 + invocation_id; the segment is collected in the
    // background and completed for `GET /v1/replies/:id` (§5.3). The room
    // cursor rides the same pump, so a polled segment advances exactly
    // like a streamed one.
    if crate::api::openai::is_async_mode(&headers) {
        let invocation_id = app.async_reply.create(&room_id).await;
        let app2 = app.clone();
        let inv = invocation_id.clone();
        let mdl = model_name.clone();
        tokio::spawn(async move {
            let _guard = guard;
            let payload = collect_segment(&mut rx, &mdl).await;
            app2.async_reply.complete(&inv, &payload.to_string()).await;
        });
        return (
            StatusCode::ACCEPTED,
            Json(json!({
                "id": invocation_id,
                "object": "chat.completion.async",
                "status": "pending",
                "conversation_id": room_id,
                "poll_url": format!("/rooms/{}/v1/replies/{}", room_id, invocation_id),
                "source": "room_segment",
            })),
        )
            .into_response();
    }

    // Non-streaming: one request = one segment, collected whole (§5.3).
    let response = collect_segment(&mut rx, &model_name).await;
    drop(guard);
    Json(response).into_response()
}

/// Collect one segment's pump events into a whole chat.completion body.
async fn collect_segment(rx: &mut mpsc::UnboundedReceiver<PumpEvent>, model_name: &str) -> Value {
    let mut text = String::new();
    loop {
        let ev = match rx.recv().await {
            Some(e) => e,
            None => break json!({"error": {"message": "stream ended"}}),
        };
        match ev {
            PumpEvent::Text(t) => text.push_str(&t),
            PumpEvent::CloseStop => {
                break json!({
                    "id": format!("chatcmpl-{}", Uuid::now_v7().simple()),
                    "object": "chat.completion",
                    "created": Utc::now().timestamp(),
                    "model": model_name,
                    "choices": [{
                        "index": 0,
                        "message": {"role": "assistant", "content": text},
                        "finish_reason": "stop"
                    }]
                })
            }
            PumpEvent::CloseToolCall { id, name, args } => {
                break json!({
                    "id": format!("chatcmpl-{}", Uuid::now_v7().simple()),
                    "object": "chat.completion",
                    "created": Utc::now().timestamp(),
                    "model": model_name,
                    "choices": [{
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": if text.is_empty() { Value::Null } else { Value::String(text) },
                            "tool_calls": [{
                                "id": id, "type": "function",
                                "function": {"name": name, "arguments": args.to_string()}
                            }]
                        },
                        "finish_reason": "tool_calls"
                    }]
                })
            }
        }
    }
}

/// Events the pump hands to a frontend (SSE or collector).
enum PumpEvent {
    Text(String),
    CloseStop,
    CloseToolCall {
        id: String,
        name: String,
        args: Value,
    },
}

struct PumpCtx {
    app: AppState,
    room_id: String,
    key_id: String,
    session_key: String,
    session_tag: String,
    agent_id: String,
    cursor: i64,
    meta: HashMap<String, Value>,
    segmented: bool,
    tools: Vec<String>,
    tx: mpsc::UnboundedSender<PumpEvent>,
}

/// The segment driver (§6.1, §6.3): drain the backlog from the cursor,
/// follow live signals, close the segment when the room goes quiet
/// (progressively longer when it never spoke), or when the turn ends.
async fn pump(ctx: PumpCtx) {
    let PumpCtx {
        app,
        room_id,
        key_id,
        session_key,
        session_tag,
        agent_id,
        mut cursor,
        meta,
        segmented,
        tools,
        tx,
    } = ctx;

    // Subscribe BEFORE draining the backlog — no gap between the two.
    let mut sub = app.rooms.subscribe(&room_id).await;
    // Lines this caller actually saw: the answer signal for resend dedup.
    let mut delivered = false;

    // Backlog first, in room_seq order.
    let backlog = app
        .room
        .room_messages_since(&room_id, cursor, 0, 1000)
        .await;
    for m in &backlog {
        if let Some(seq) = m.room_seq {
            cursor = cursor.max(seq);
        }
        if m.sender.participant_id == agent_id
            && m.metadata.get("caller_session").and_then(|v| v.as_str()) == Some(&session_tag)
        {
            continue; // our own speech, already in the caller's context
        }
        let line = format_room_line(m);
        if tx.send(PumpEvent::Text(line)).is_err() {
            return;
        }
        delivered = true;
    }
    advance_cursor(&app, &room_id, &key_id, &session_key, cursor).await;

    // An owner tool call that landed between two segments of this triple
    // runs now, on the request that came for it (§6.6).
    if let Some(inv) = app.rooms.take_invoke(&room_id, &key_id, &session_key).await {
        app.rooms
            .segment_record_outcome(&room_id, &key_id, &session_key, true)
            .await;
        close_with_invoke(&tx, inv);
        return;
    }

    let quiet = crate::rooms::segment_quiet_secs(&meta);
    let seg_max = crate::rooms::segment_max_secs(&meta);
    let deep_idle = Duration::from_secs(crate::rooms::deep_idle_mins(&meta) * 60);

    // Resend dedup (§7.2): keyed (room, session tag) at ingest, cleared
    // here when the room actually answered this caller — a repeated "继续"
    // after an answer is a new turn, not a replay.
    let dedup_key = format!("{}\u{1f}{}", room_id, session_tag);
    // `had_content` counts any backlog row (including our own filtered
    // speech) and only drives segment timing; `delivered` (above) counts
    // lines this caller actually saw and is the answer signal for dedup.
    let mut had_content = !backlog.is_empty();
    let mut last_content = std::time::Instant::now();
    let empty_streak = app
        .rooms
        .segment_empty_streak(&room_id, &key_id, &session_key)
        .await;
    let no_content_limit = match empty_streak {
        0 => 20.min(seg_max),
        1 => 40.min(seg_max),
        _ => seg_max,
    };
    let started = std::time::Instant::now();

    let mut tick = tokio::time::interval(Duration::from_millis(250));
    tick.tick().await;

    loop {
        let sig = tokio::select! {
            _ = tick.tick() => None,
            s = sub.recv() => Some(s),
        };

        match sig {
            Some(Ok(RoomSignal::Message(m))) => {
                if let Some(seq) = m.room_seq {
                    if seq <= cursor {
                        continue; // already streamed from the backlog
                    }
                    cursor = seq;
                }
                // Merge window: hold briefly for follow-up speech (§6.1.4).
                let mut batch = vec![m];
                while let Ok(Ok(RoomSignal::Message(m2))) =
                    tokio::time::timeout(crate::async_reply::merge_window(), sub.recv()).await
                {
                    if let Some(seq) = m2.room_seq {
                        cursor = cursor.max(seq);
                    }
                    batch.push(m2);
                }
                for m in &batch {
                    if m.sender.participant_id == agent_id
                        && m.metadata.get("caller_session").and_then(|v| v.as_str())
                            == Some(&session_tag)
                    {
                        continue;
                    }
                    let line = format_room_line(m);
                    if tx.send(PumpEvent::Text(line)).is_err() {
                        return;
                    }
                    delivered = true;
                }
                advance_cursor(&app, &room_id, &key_id, &session_key, cursor).await;
                had_content = true;
                last_content = std::time::Instant::now();
            }
            Some(Ok(RoomSignal::EndTurn { reason })) => {
                let _ = reason;
                app.rooms
                    .segment_record_outcome(&room_id, &key_id, &session_key, had_content)
                    .await;
                if delivered {
                    crate::session::turn_answered(&dedup_key);
                }
                let _ = tx.send(PumpEvent::CloseStop);
                return;
            }
            Some(Ok(RoomSignal::ToolInvoke {
                target_key,
                target_session,
            })) => {
                // Not ours: another caller's stream executes this one. The
                // call text already reached us as a room log line.
                if target_key != key_id || target_session != session_key {
                    continue;
                }
                // A pump whose client already hung up must leave the call
                // parked for the next request instead of eating it.
                if tx.is_closed() {
                    return;
                }
                let Some(inv) = app.rooms.take_invoke(&room_id, &key_id, &session_key).await else {
                    continue; // already taken (a superseded twin got it)
                };
                app.rooms
                    .segment_record_outcome(&room_id, &key_id, &session_key, had_content)
                    .await;
                crate::session::turn_answered(&dedup_key);
                close_with_invoke(&tx, inv);
                return;
            }
            Some(Err(tokio::sync::broadcast::error::RecvError::Lagged(_))) => {
                // We fell behind: resync the backlog from the cursor.
                let missed = app
                    .room
                    .room_messages_since(&room_id, cursor, 0, 1000)
                    .await;
                for m in &missed {
                    if let Some(seq) = m.room_seq {
                        cursor = cursor.max(seq);
                    }
                    if m.sender.participant_id == agent_id
                        && m.metadata.get("caller_session").and_then(|v| v.as_str())
                            == Some(&session_tag)
                    {
                        continue; // our own speech, same as the backlog pass
                    }
                    let line = format_room_line(m);
                    if tx.send(PumpEvent::Text(line)).is_err() {
                        return;
                    }
                    delivered = true;
                }
                advance_cursor(&app, &room_id, &key_id, &session_key, cursor).await;
                had_content = true;
                last_content = std::time::Instant::now();
            }
            Some(Err(tokio::sync::broadcast::error::RecvError::Closed)) => return,
            None => {
                if !segmented {
                    continue; // fallback mode: only end.turn / idle release closes
                }
                // Deep idle: stop segmenting, just keep the request open with
                // heartbeats (the frontend's keepalive ticks continue). Speech
                // re-arms segmenting immediately (§6.3).
                let last_activity = crate::rooms::RoomHub::last_activity(&app, &room_id).await;
                let deep = last_activity
                    .map(|t| Utc::now() - t > chrono::Duration::from_std(deep_idle).unwrap())
                    .unwrap_or(false);
                if deep {
                    continue;
                }
                let due = if had_content {
                    last_content.elapsed() >= Duration::from_secs(quiet)
                } else {
                    started.elapsed() >= Duration::from_secs(no_content_limit)
                };
                if due {
                    app.rooms
                        .segment_record_outcome(&room_id, &key_id, &session_key, had_content)
                        .await;
                    if delivered {
                        crate::session::turn_answered(&dedup_key);
                    }
                    let (name, id) = pick_keepalive_tool(&tools);
                    let _ = tx.send(PumpEvent::CloseToolCall {
                        id,
                        name,
                        args: json!({}),
                    });
                    return;
                }
            }
        }
    }
}

/// Close the segment with the owner's real tool call (and the words the
/// owner said with it, as content before the call).
fn close_with_invoke(tx: &mpsc::UnboundedSender<PumpEvent>, inv: crate::rooms::PendingInvoke) {
    if let Some(t) = inv.text.filter(|t| !t.trim().is_empty()) {
        let _ = tx.send(PumpEvent::Text(t));
    }
    let _ = tx.send(PumpEvent::CloseToolCall {
        id: inv.invocation_id,
        name: inv.tool_id,
        args: inv.input,
    });
}

/// Pick the keepalive tool from the client's own declared tools (§6.2).
fn pick_keepalive_tool(declared: &[String]) -> (String, String) {
    let name = segmenter::KEEPALIVE_TOOL_WHITELIST
        .iter()
        .find(|w| declared.iter().any(|d| d == *w))
        .map(|s| s.to_string())
        .unwrap_or_else(|| segmenter::KEEPALIVE_FALLBACK_TOOL.to_string());
    let id = format!(
        "{}{}",
        segmenter::KEEPALIVE_ID_PREFIX,
        Uuid::now_v7().simple()
    );
    (name, id)
}

/// One room message as streamed text: `[name] text` + a blank line (§6.8).
fn format_room_line(m: &Message) -> String {
    let name = m
        .sender
        .display_name
        .clone()
        .unwrap_or_else(|| m.sender.participant_id.clone());
    let name = match m.metadata.get("caller_session").and_then(|v| v.as_str()) {
        Some(tag) => format!("{} · {}", name, tag),
        None => name,
    };
    let text = m.content.as_text().unwrap_or("");
    format!("[{}] {}\n\n", name, text)
}

async fn advance_cursor(app: &AppState, room_id: &str, key_id: &str, session_key: &str, seq: i64) {
    app.room
        .room_cursor_set(room_id, key_id, session_key, seq)
        .await;
}

/// GET /rooms/:room_id/v1/models — the room's model is its name.
pub async fn room_list_models(
    State(app): State<AppState>,
    Path(room_id): Path<String>,
) -> Response {
    match app.conversation.get(&room_id).await {
        Some(c) if c.conversation_type == ConversationType::Group => {
            let name = c.title.clone().unwrap_or_else(|| room_id.clone());
            Json(json!({
                "object": "list",
                "data": [room_model_object(&name)],
                "has_more": false,
                "first_id": name,
                "last_id": name,
            }))
            .into_response()
        }
        _ => err(StatusCode::NOT_FOUND, "room_not_found", "No such room."),
    }
}

/// GET /rooms/:room_id/v1/models/:model_id
pub async fn room_get_model(
    State(app): State<AppState>,
    Path((room_id, model_id)): Path<(String, String)>,
) -> Response {
    match app.conversation.get(&room_id).await {
        Some(c) if c.conversation_type == ConversationType::Group => {
            let mut m = room_model_object(&c.title.unwrap_or_else(|| room_id.clone()));
            m["id"] = Value::String(model_id);
            Json(m).into_response()
        }
        _ => err(StatusCode::NOT_FOUND, "room_not_found", "No such room."),
    }
}

fn room_model_object(name: &str) -> Value {
    json!({
        "id": name,
        "object": "model",
        "type": "model",
        "display_name": name,
        "created": 1700000000,
        "owned_by": "openhuman",
        "name": name,
        "context_window": 1_000_000,
        "max_output_tokens": 131_072,
        "capabilities": {"vision": true, "tools": true, "streaming": true}
    })
}
