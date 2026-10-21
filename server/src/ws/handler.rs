//! WebSocket handler — `/ws` endpoint.
//!
//! Phase 6: Realtime message routing layer.
//! Phase 7: Agent capability manifest + tool invocation transport.
//!
//! # Connection Lifecycle
//!
//! 1. **Connect** — client opens `ws://host/ws?api_key=ohk_xxx`
//! 2. **Authenticate** — server resolves the API key → `AuthPrincipal`
//! 3. **Register** — connection is added to `ConnectionRegistry` on `AppState`
//! 4. **Connected** — server sends `session.connected` event
//! 5. **Drain pending** — all `Pending` messages for the human's conversations
//!    are pushed to the client (offline → online catch-up)
//! 6. **Message loop** — server pushes `message.received`; client sends `reply.send`,
//!    `capability.manifest`, or `tool.invoke`
//! 7. **Disconnect** — unregister from `ConnectionRegistry`; SSE timeout naturally
//!
//! # Phase 7: Capability & Tool Invocation
//!
//! The WS handler now supports two new client→server messages:
//! - `capability.manifest` — agent publishes tools; server stores + notifies human
//! - `tool.invoke` — human requests a tool; server routes to agent via SSE

use chrono::Utc;
use futures::stream::StreamExt;
use futures::SinkExt;
use serde::Deserialize;
use std::time::Duration;
use uuid::Uuid;

use axum::extract::ws::{Message as WsMessage, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::http::HeaderMap;
use axum::response::Response;

use crate::model::content::ContentBlock;
use crate::model::identity::ParticipantRef;
use crate::model::message::{Message, MessageStatus};
use crate::model::tool_invocation::ToolInvoke;
use crate::storage::AppState;
use crate::ws::protocol;

/// How often the server pings an open human WebSocket.
///
/// Comfortably below the idle timeout imposed by intermediaries (~100s), so
/// a console that is merely idle never looks dead.
const WS_PING_SECS: u64 = 30;

/// Query parameters for the `/ws` endpoint.
#[derive(Debug, Deserialize)]
pub struct WsQuery {
    /// API key — same Bearer key used for the HTTP API.
    pub api_key: Option<String>,
    pub token: Option<String>,
    pub authorization: Option<String>,
    /// Optional mobile push token (FCM device token).
    pub device_token: Option<String>,
}

/// Handler for `GET /ws` — WebSocket upgrade.
///
/// The API key is accepted from the `Authorization: Bearer` header first,
/// falling back to the `?api_key=` / `?token=` / `?authorization=` query
/// parameters for clients that cannot set headers on the upgrade request
/// (notably browsers). Header auth is preferred: query strings end up in
/// proxy and server access logs, headers do not.
pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(app): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<WsQuery>,
) -> Response {
    ws.on_upgrade(move |socket| handle_connection(socket, app, headers, q))
}

/// Main connection loop after WebSocket upgrade.
async fn handle_connection(socket: WebSocket, app: AppState, headers: HeaderMap, q: WsQuery) {
    tracing::debug!("WebSocket connection received");

    // 1. Resolve the API key: Authorization header first, query params after.
    let raw_key = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer ").map(|s| s.to_string()))
        .or_else(|| {
            q.api_key
                .clone()
                .or(q.token.clone())
                .or(q.authorization.clone())
                .map(|s| {
                    s.strip_prefix("Bearer ")
                        .map(|t| t.to_string())
                        .unwrap_or(s)
                })
        });

    let raw_key = match raw_key {
        Some(k) => k,
        None => {
            tracing::warn!("WebSocket rejected: no API key in query params");
            return;
        }
    };

    // 2. Authenticate via the identity repository.
    let principal = app.identity.resolve_principal(&raw_key).await;

    let (human_id, display_name, agent_id) = match principal {
        Some(p) if !p.api_key.scope.may_respond() => {
            tracing::warn!(
                "WebSocket rejected: key scope '{}' cannot answer as the human",
                p.api_key.scope.as_str()
            );
            return;
        }
        Some(p) => (
            p.human.id.clone(),
            p.human.display_name.clone(),
            p.agent.id.clone(),
        ),
        None => {
            tracing::warn!("WebSocket rejected: invalid API key");
            return;
        }
    };

    tracing::info!(
        "WebSocket authenticated: human_id={}, agent_id={}, name={}",
        human_id,
        agent_id,
        display_name
    );

    // If a mobile device token was provided in query, register it for offline push notifications
    if let Some(token) = q.device_token {
        crate::notification::register_device_token(human_id.clone(), token);
    }

    // 3. Generate a unique device_id for this connection.
    let device_id = format!("dev_{}", Uuid::now_v7().simple());

    // 4. Split socket into sender/receiver.
    let (sender, mut receiver) = socket.split();

    // 5. Create an mpsc channel for pushing events from server -> client.
    let (push_tx, mut push_rx) = tokio::sync::mpsc::unbounded_channel::<String>();

    // 6. Register this connection in the shared ConnectionRegistry on AppState.
    app.connections
        .register(&human_id, &device_id, push_tx.clone())
        .await;

    // 7. Send `session.connected` event immediately.
    let connected_event = protocol::session_connected(&human_id, &display_name);
    let _ = push_tx.send(protocol::event_to_json(&connected_event));

    // 8. Drain pending messages for the human's conversations.
    drain_pending_messages(&app, &human_id, &push_tx).await;

    // 8b. Tell whoever is waiting that a human just showed up. Only when a
    //     request is actually in flight: announcing presence into the void
    //     would park the notice and deliver it out of context later.
    announce_online(&app, &human_id).await;

    // 9. Spawn the sender task — drains push_rx and writes to the WebSocket.
    //
    //    It also pings on a timer. A quiet socket looks dead to everything
    //    in between — the CDN closes idle connections at roughly 100s — and
    //    a human who is simply reading sends nothing for minutes at a time.
    //    Without traffic of our own the console silently stops receiving
    //    pushes even though the human is sitting right there.
    let mut send_task = tokio::spawn(async move {
        let mut sender = sender;
        let mut ping = tokio::time::interval(Duration::from_secs(WS_PING_SECS));
        // First tick resolves immediately; skip it so we do not ping twice
        // in the same instant as `session.connected`.
        ping.tick().await;

        loop {
            tokio::select! {
                maybe_msg = push_rx.recv() => {
                    match maybe_msg {
                        Some(msg) => {
                            if sender.send(WsMessage::Text(msg)).await.is_err() {
                                break;
                            }
                        }
                        // Channel closed — nothing left to push.
                        None => break,
                    }
                }
                _ = ping.tick() => {
                    if sender.send(WsMessage::Ping(Vec::new())).await.is_err() {
                        break;
                    }
                }
            }
        }
    });

    // 10. Receiver task — reads from the WebSocket client.
    let app_clone = app.clone();
    let human_id_clone = human_id.clone();
    let agent_id_clone = agent_id.clone();
    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                WsMessage::Text(text) => {
                    handle_client_message(&text, &app_clone, &human_id_clone, &agent_id_clone)
                        .await;
                }
                WsMessage::Close(_) => {
                    tracing::debug!("WebSocket client closed connection");
                    break;
                }
                _ => {}
            }
        }
    });

    // 11. Wait for either task to finish, then cleanup.
    tokio::select! {
        _ = &mut send_task => {
            recv_task.abort();
        }
        _ = &mut recv_task => {
            send_task.abort();
        }
    }

    // 12. Unregister from the connection registry.
    app.connections.unregister(&human_id, &device_id).await;

    tracing::info!(
        "WebSocket disconnected: human_id={}, device_id={}",
        human_id,
        device_id
    );
}

/// Drain pending messages for the human's conversations.
///
/// When a human connects, the server looks up all conversations where
/// this human is a participant, and pushes any `Pending` status messages
/// to the newly connected client. This provides offline catch-up.
pub(crate) async fn drain_pending_messages(
    app: &AppState,
    human_id: &str,
    push_tx: &tokio::sync::mpsc::UnboundedSender<String>,
) {
    // Only what has not reached a device yet.
    //
    // Replaying every message in every conversation looked harmless on a
    // fresh account and was not: a long-lived conversation re-sent its whole
    // history on every reconnect, so the human watched messages they had
    // already answered arrive again, and the burst itself was large enough
    // to swamp the connection. Full history belongs to a history endpoint;
    // this channel carries the backlog.
    let pending = app.message.list_undelivered(human_id).await;
    if pending.is_empty() {
        return;
    }

    let mut pushed = Vec::with_capacity(pending.len());
    let mut discarded = Vec::new();

    for msg in &pending {
        // A tool result left in the backlog is still a tool result: it
        // must settle its call, not show up as words from the caller.
        if msg.metadata.get("openai_role").and_then(|v| v.as_str()) == Some("tool") {
            if let Some(call_id) = msg.metadata.get("tool_call_id").and_then(|v| v.as_str()) {
                let tool_id = crate::session::tool_name_for(&msg.conversation_id, call_id)
                    .unwrap_or_else(|| "unknown".to_string());
                let output =
                    serde_json::Value::String(msg.content.as_text().unwrap_or("").to_string());
                let event = protocol::tool_result_event(
                    &msg.conversation_id,
                    call_id,
                    &tool_id,
                    "success",
                    Some(&output),
                    None,
                );
                if push_tx.send(protocol::event_to_json(&event)).is_err() {
                    break;
                }
            }
            pushed.push(msg.id.clone());
            continue;
        }

        // Not pushed, but not left pending either: without this they are
        // re-examined on every reconnect and never cleared, so the
        // backlog grows without ever being displayed.
        let skippable = msg.sender.participant_id == human_id
            || msg.visibility != crate::model::message::MessageVisibility::HumanVisible;

        if skippable {
            discarded.push(msg.id.clone());
            continue;
        }

        let images: Vec<String> = msg
            .metadata
            .get("images")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();

        let mut event = if images.is_empty() {
            protocol::message_received(
                &msg.conversation_id,
                &msg.id,
                &msg.sender.participant_id,
                &format!("{:?}", msg.sender.participant_type).to_lowercase(),
                msg.sender.display_name.as_deref(),
                msg.content.as_text().unwrap_or(""),
            )
        } else {
            protocol::message_received_with_images(
                &msg.conversation_id,
                &msg.id,
                &msg.sender.participant_id,
                &format!("{:?}", msg.sender.participant_type).to_lowercase(),
                msg.sender.display_name.as_deref(),
                msg.content.as_text().unwrap_or(""),
                &images,
            )
        };
        // The same request context a live push carries (client, auxiliary
        // call and its output contract, raw injected parts): a message that
        // waited for the seat must read exactly like one delivered at once.
        for key in ["request", "raw_tail"] {
            if let (Some(v), Some(obj)) = (msg.metadata.get(key), event.data.as_object_mut()) {
                obj.insert(key.to_string(), v.clone());
            }
        }

        if push_tx.send(protocol::event_to_json(&event)).is_err() {
            break;
        }
        pushed.push(msg.id.clone());
    }

    app.message.mark_delivered(&pushed).await;

    // Same bookkeeping for the skipped ones, so they stop being
    // re-examined on every subsequent reconnect.
    if !discarded.is_empty() {
        app.message.mark_delivered(&discarded).await;
    }
}

/// Process a single client → server message.
pub(crate) async fn handle_client_message(
    raw: &str,
    app: &AppState,
    human_id: &str,
    agent_id: &str,
) {
    let event = match protocol::ClientMessage::from_json(raw) {
        Ok(e) => e,
        Err(e) => {
            tracing::warn!("Invalid WS message from {}: {} — raw: {}", human_id, e, raw);
            return;
        }
    };

    match event {
        protocol::ClientMessage::ReplySend {
            conversation_id,
            text,
            invocation_id,
        } => {
            handle_reply_send(
                app,
                &conversation_id,
                &text,
                invocation_id.as_deref(),
                human_id,
            )
            .await;
        }
        protocol::ClientMessage::PresenceUpdate { status } => {
            handle_presence_update(app, &status, human_id).await;
        }
        protocol::ClientMessage::CapabilityManifest {
            agent_id: msg_agent_id,
            capabilities,
            context,
        } => {
            handle_capability_manifest(app, &msg_agent_id, capabilities, context, human_id).await;
        }
        protocol::ClientMessage::ToolInvoke {
            conversation_id,
            invocation_id,
            tool_id,
            input,
            text,
        } => {
            handle_tool_invoke(
                app,
                &conversation_id,
                &invocation_id,
                &tool_id,
                input,
                text,
                human_id,
                agent_id,
            )
            .await;
        }
        protocol::ClientMessage::EndTurn { conversation_id } => {
            handle_end_turn(app, &conversation_id, human_id).await;
        }
    }
}

/// Announce that the human came online, to any request already waiting.
///
/// The notice is a plain text payload, so it arrives as streamed prose and
/// the turn stays open for the real answer — it must not resolve the
/// request, or the human would lose their chance to reply.
///
/// Conversations with nothing in flight are skipped: the notice would only
/// end up parked in the outbound queue and surface much later, detached
/// from whatever it was meant to reassure.
pub(crate) async fn announce_online(app: &AppState, human_id: &str) {
    let notice = std::env::var("OPENHUMAN_ONLINE_NOTICE")
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| "[OpenHuman 提示]: 人类专家已上线，马上回复你。\n\n".to_string());

    for conversation_id in app.reply.conversations_with_waiters().await {
        let belongs = match app.conversation.get(&conversation_id).await {
            Some(c) => c.human_id() == Some(human_id),
            None => false,
        };
        if !belongs {
            continue;
        }
        if app.reply.deliver(&conversation_id, &notice).await {
            tracing::info!(
                conversation_id = %conversation_id,
                "Announced human online to a waiting request"
            );
        }
    }
}

/// Handle `reply.send` from the human client.
///
/// When `invocation_id` is present the reply belongs to a turn submitted in
/// asynchronous mode. That invocation is completed first — nobody is holding
/// a blocking request open for it, so the reply channel would just drop it.
/// The synchronous path is still attempted afterwards so a mixed deployment
/// (async turn answered while a blocking request happens to be waiting) does
/// not lose the reply either.
async fn handle_reply_send(
    app: &AppState,
    conversation_id: &str,
    text: &str,
    invocation_id: Option<&str>,
    human_id: &str,
) {
    // 0. Complete a pending async invocation, if this reply targets one.
    let mut async_completed = false;
    if let Some(inv_id) = invocation_id {
        async_completed = app.async_reply.complete(inv_id, text).await;
        if async_completed {
            tracing::info!(
                "Async invocation completed: invocation_id={}, conversation_id={}",
                inv_id,
                conversation_id
            );
        } else {
            tracing::warn!(
                "reply.send carried unknown invocation_id={} — falling back to reply channel",
                inv_id
            );
        }
    }

    // 1. Deliver the human's reply to the waiting SSE/HTTP handler.
    //
    // NOTE (multi-turn): the reply channel is NOT removed here — the SSE
    // stream stays open so the human can send more replies. The channel
    // is removed by the SSE handler itself when it receives the
    // end-of-turn signal (or a tool call).
    let channel_delivered = app.reply.deliver(conversation_id, text).await;
    let mut delivered = channel_delivered || async_completed;

    // 1b. Fall back to the newest pending invocation for this conversation.
    //
    // This is the normal path after a blocking request timed out and handed
    // the turn off to async mode: the message was already on screen, so the
    // console has no `invocation_id` to echo. Without this the reply would
    // land nowhere and the turn would be lost even though the human did
    // answer.
    // Staged rather than completed outright: the human may still be about to
    // tap a tool, and completing now would leave that call with no
    // invocation to land on.
    if !delivered
        && app
            .async_reply
            .stage_for_conversation(conversation_id, text)
            .await
    {
        tracing::info!(
            "Reply staged for this async turn: conversation_id={}",
            conversation_id
        );
        delivered = true;
    }

    // 1c. Still nowhere to put it — no request is in flight at all. Park the
    //     reply so the next request for this conversation carries it out,
    //     instead of the human's answer evaporating.
    if !delivered {
        app.outbound.enqueue(conversation_id, text).await;
        tracing::info!(
            "Reply parked for the next request: conversation_id={}",
            conversation_id
        );
    }

    // 2. Store the reply ONLY if no SSE handler picked it up (agent
    //    offline, or answered in async mode where no SSE handler exists).
    //    When delivered to a live SSE handler, that handler stores it
    //    itself — storing here too would duplicate the message.
    if !channel_delivered {
        app.message
            .insert(Message {
                id: format!("msg_{}", Uuid::now_v7().simple()),
                conversation_id: conversation_id.to_string(),
                sender: ParticipantRef::human_named(human_id, "You"),
                content: ContentBlock::text(text),
                attachments: Vec::new(),
                metadata: std::collections::HashMap::new(),
                status: MessageStatus::Sent,
                visibility: crate::model::message::MessageVisibility::HumanVisible,
                created_at: Utc::now(),
            })
            .await;
    }

    // 2. Send `reply.delivered` ack to the human's WS client.
    //
    // NOTE: the human's reply is stored by the SSE handler when it
    // processes the payload (it needs the conversation lookup to resolve
    // the human's identity). Do NOT store it here — that would duplicate
    // the message.
    let ack = protocol::reply_delivered(conversation_id, delivered);
    let ack_json = protocol::event_to_json(&ack);

    // Push to all of this human's connected devices.
    app.connections.send_to_human(human_id, &ack_json).await;

    if delivered {
        tracing::info!("Reply delivered: conversation_id={}", conversation_id);
    } else {
        tracing::warn!(
            "Reply stored but no pending SSE: conversation_id={}",
            conversation_id
        );
    }
}

/// Handle `end.turn` from the human client.
///
/// Delivers the end-of-turn sentinel to the waiting SSE stream, which
/// terminates it with `finish_reason: stop`. If no SSE stream is waiting
/// (agent idle), this is a no-op.
async fn handle_end_turn(app: &AppState, conversation_id: &str, human_id: &str) {
    tracing::info!("End turn requested: conversation_id={}", conversation_id);

    let delivered = app.reply.deliver(conversation_id, "__END_TURN__").await;

    let ack = protocol::reply_delivered(conversation_id, delivered);
    let ack_json = protocol::event_to_json(&ack);
    app.connections.send_to_human(human_id, &ack_json).await;

    if !delivered {
        tracing::debug!(
            "End turn had no pending SSE (agent idle): conversation_id={}",
            conversation_id
        );
    }
}

/// Handle `presence.update` from the human client.
///
/// The status is persisted on the human identity so agents and other
/// devices can tell "away" from "offline" without guessing from socket
/// state. Unknown status strings are ignored rather than stored.
async fn handle_presence_update(app: &AppState, status: &str, human_id: &str) {
    use crate::model::identity::HumanStatus;

    let parsed = match status.trim().to_lowercase().as_str() {
        "online" => Some(HumanStatus::Online),
        "away" => Some(HumanStatus::Away),
        "offline" => Some(HumanStatus::Offline),
        other => {
            tracing::warn!(
                "Ignoring unknown presence status from {}: {}",
                human_id,
                other
            );
            None
        }
    };

    if let Some(s) = parsed {
        let stored = app.identity.set_human_status(human_id, s).await;
        tracing::info!(
            "Presence update from {}: {} (stored={})",
            human_id,
            status,
            stored
        );
    }
}

/// Handle `capability.manifest` from an agent.
///
/// The agent publishes its tools and optional context. The server:
/// 1. Stores capabilities via `CapabilityRepository::set_capabilities`
/// 2. Stores context via `ContextRepository::set_context` (if present)
/// 3. Pushes `capability.updated` to the bound human's connected devices
async fn handle_capability_manifest(
    app: &AppState,
    agent_id: &str,
    capabilities: Vec<crate::model::agent_capability::AgentCapability>,
    context: Option<crate::model::agent_context::AgentContext>,
    human_id: &str,
) {
    tracing::info!(
        "Capability manifest from agent={}: {} tools",
        agent_id,
        capabilities.len()
    );

    // 1. Store capabilities.
    app.capability
        .set_capabilities(agent_id, capabilities.clone())
        .await;

    // 2. Store context if present.
    if let Some(ref ctx) = context {
        app.context.set_context(agent_id, ctx.clone()).await;
    }

    // 3. Push `capability.updated` to all human devices.
    let event = protocol::capability_updated(human_id, agent_id, &capabilities, context.as_ref());
    let event_json = protocol::event_to_json(&event);
    app.connections.send_to_human(human_id, &event_json).await;
}

/// Handle `tool.invoke` from the human client.
///
/// The human requests an agent tool invocation. The server:
/// 1. Looks up the capability to validate the tool exists
/// 2. Delivers the invoke request to the agent's SSE stream (piggybacks on
///    the existing `ReplyRegistry` — the agent's SSE handler will receive
///    a JSON-encoded `tool.invoke` object instead of a plain text reply)
/// 3. When the agent responds with `tool.result`, the server pushes it to
///    the human's WS
#[allow(clippy::too_many_arguments)]
async fn handle_tool_invoke(
    app: &AppState,
    conversation_id: &str,
    invocation_id: &str,
    tool_id: &str,
    input: serde_json::Value,
    text: Option<String>,
    human_id: &str,
    agent_id: &str,
) {
    // 1. Validate the tool exists. The tools that count are the ones the
    //    caller declared in this conversation's own last request: the
    //    responder's key belongs to a different agent than the caller's, so
    //    looking up the responder's agent alone rejects every real tool.
    let conv_has_tool = crate::session::get_context(conversation_id)
        .and_then(|c| c.get("tools").cloned())
        .and_then(|t| t.as_array().cloned())
        .map(|a| {
            a.iter()
                .any(|t| t.get("id").and_then(|v| v.as_str()) == Some(tool_id))
        });
    let known = conv_has_tool == Some(true)
        || app
            .capability
            .get_capability(agent_id, tool_id)
            .await
            .is_some();
    if !known {
        let event = protocol::error_event(
            human_id,
            "tool_not_found",
            &format!("Tool '{}' not found for agent '{}'", tool_id, agent_id),
        );
        let event_json = protocol::event_to_json(&event);
        app.connections.send_to_human(human_id, &event_json).await;
        return;
    }

    // 2. Build the invoke payload — piggyback on the reply channel.
    //    The agent's SSE handler will detect this JSON structure
    //    (has `type: "tool.invoke"`) and handle it as a tool request,
    //    not a text reply.
    let invoke = ToolInvoke {
        invocation_id: invocation_id.to_string(),
        tool_id: tool_id.to_string(),
        input,
    };

    // Companion prose must ride along, otherwise it is dropped the moment a
    // tool is involved and the human's words never reach the agent.
    let mut payload = serde_json::json!({
        "type": "tool.invoke",
        "invocation_id": invoke.invocation_id,
        "tool_id": invoke.tool_id,
        "input": invoke.input,
    });
    if let Some(prose) = text.filter(|t| !t.trim().is_empty()) {
        payload["text"] = serde_json::Value::String(prose);
    }
    let invoke_json = payload.to_string();

    // Correlation metadata for the stored copy: an async turn resolves
    // through the registry and never passes through the SSE/NON-streaming
    // handlers, so without storing it here a later `role:"tool"` result
    // cannot recover which tool it belongs to.
    let mut invoke_meta = std::collections::HashMap::new();
    invoke_meta.insert(
        "tool_call_id".to_string(),
        serde_json::Value::String(invocation_id.to_string()),
    );
    invoke_meta.insert(
        "tool_id".to_string(),
        serde_json::Value::String(tool_id.to_string()),
    );

    // 3. Deliver via the reply channel (piggyback on SSE stream).
    //
    //    In async mode there is no reply channel — the turn is parked in
    //    the async registry instead — so fall back to completing the newest
    //    pending invocation for this conversation. Without this a tool
    //    invoke against an async turn is reported as "agent not connected"
    //    and the invocation stays pending forever.
    let channel_delivered = app.reply.deliver(conversation_id, &invoke_json).await;
    let mut delivered = channel_delivered;
    if !delivered {
        delivered = app
            .async_reply
            .stage_for_conversation(conversation_id, &invoke_json)
            .await;
        if delivered {
            tracing::info!(
                "Tool invoke staged for this async turn: conversation_id={}, invocation_id={}",
                conversation_id,
                invocation_id
            );
        }
    }

    // No request in flight: park it like a text reply so the next request
    // picks it up, rather than telling the human the agent is unreachable
    // and throwing the invocation away.
    if !delivered {
        app.outbound.enqueue(conversation_id, &invoke_json).await;
        tracing::info!(
            "Tool invoke parked for the next request: conversation_id={}, invocation_id={}",
            conversation_id,
            invocation_id
        );
    }

    tracing::info!(
        "Tool invoke: invocation_id={}, tool_id={}, delivered={}",
        invocation_id,
        tool_id,
        delivered
    );

    // Persist the call when it did not go through a live handler: the SSE and
    // non-streaming handlers store their own copy, but async turns resolve
    // inside the registry and would otherwise leave no trace for a later
    // `role:"tool"` result to match against.
    if !channel_delivered {
        app.message
            .insert(Message {
                id: format!("msg_{}", Uuid::now_v7().simple()),
                conversation_id: conversation_id.to_string(),
                sender: ParticipantRef::human_named(human_id, "You"),
                content: ContentBlock::text(&invoke_json),
                attachments: Vec::new(),
                metadata: invoke_meta,
                status: MessageStatus::Sent,
                visibility: crate::model::message::MessageVisibility::HumanVisible,
                created_at: Utc::now(),
            })
            .await;
    }

    if !delivered {
        let event = protocol::error_event(
            human_id,
            "queued",
            "No request in flight — the invocation is queued and will be sent with the next request.",
        );
        let event_json = protocol::event_to_json(&event);
        app.connections.send_to_human(human_id, &event_json).await;
    }
}
