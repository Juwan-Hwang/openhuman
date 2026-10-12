//! Integration tests: Phase 6 Realtime Message Routing.
//!
//! Tests cover:
//! 1. `test_agent_message_pushes_to_online_human` — full Agent→WS→Human→WS→SSE→Agent chain
//! 2. `test_human_offline_message_persisted_and_drained_on_reconnect`
//! 3. `test_multi_device_fanout` — same human, 2 devices, both receive
//! 4. `test_ws_authentication` — valid/invalid/missing key

use openhuman_server::build_router;
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::AppState;

use futures::stream::StreamExt;
use futures::SinkExt;
use tokio_tungstenite::tungstenite::Message as WsMessage;

const DEMO_KEY: &str = "ohk_demo_alice_codex";

fn test_app() -> axum::Router {
    let store = MemoryStore::seeded();
    let state = AppState::from_store(store);
    build_router(state)
}

/// Helper: extract the next JSON text message from a WS stream.
async fn next_json(
    ws: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> serde_json::Value {
    loop {
        match ws.next().await {
            Some(Ok(WsMessage::Text(text))) => {
                return serde_json::from_str(&text)
                    .unwrap_or_else(|_| panic!("Failed to parse WS text as JSON: {}", text));
            }
            Some(Ok(WsMessage::Ping(_))) => continue,
            Some(Ok(WsMessage::Pong(_))) => continue,
            Some(Ok(WsMessage::Binary(_))) => continue,
            Some(Ok(WsMessage::Frame(_))) => continue,
            Some(Ok(WsMessage::Close(_))) => {
                panic!("WS closed before receiving expected message")
            }
            Some(Err(e)) => panic!("WS error: {}", e),
            None => panic!("WS stream ended"),
        }
    }
}

/// Helper: like `next_json` but skips `capability.updated` events.
///
/// Phase 7.1.1: The HTTP handler auto-upserts context on every request,
/// pushing a `capability.updated` event before `message.received`.
async fn next_json_skip_capability(
    ws: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> serde_json::Value {
    loop {
        let ev = next_json(ws).await;
        if ev["event_type"] != "capability.updated" {
            return ev;
        }
    }
}

// ════════════════════════════════════════════════════════════
// 1. Full chain: Agent → WS → Human → WS → SSE → Agent
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn test_agent_message_pushes_to_online_human() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let ws_url = format!("ws://{}/ws?api_key={}", addr, DEMO_KEY);

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    // 1. Human connects via WebSocket.
    let (mut ws_stream, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("WS connect failed");

    // 2. Receive `session.connected` event (aligned with event.md).
    let connected = next_json(&mut ws_stream).await;
    assert_eq!(
        connected["event_type"], "session.connected",
        "Expected session.connected, got: {}",
        connected
    );
    assert_eq!(connected["data"]["human_id"], "hum_demo_alice");

    // 3. Agent sends a streaming chat completion request.
    let http_client = reqwest::Client::new();
    let agent_task = tokio::spawn({
        let client = http_client.clone();
        async move {
            client
                .post(format!("http://{}/v1/chat/completions", addr))
                .header("Authorization", format!("Bearer {}", DEMO_KEY))
                .json(&serde_json::json!({
                    "model": "human",
                    "messages": [
                        {"role": "user", "content": "Review my PR please"}
                    ],
                    "stream": true
                }))
                .send()
                .await
                .unwrap()
        }
    });

    // 4. Human receives `message.received` event via WebSocket
    //    (pushed by the server after the agent's message was stored).
    let msg_event = next_json_skip_capability(&mut ws_stream).await;
    assert_eq!(
        msg_event["event_type"], "message.received",
        "Expected message.received, got: {}",
        msg_event
    );
    assert_eq!(
        msg_event["data"]["text"], "Review my PR please",
        "Wrong message text"
    );
    assert_eq!(
        msg_event["data"]["sender_id"], "agt_demo_codex",
        "Wrong sender"
    );

    let conversation_id = msg_event["conversation_id"].as_str().unwrap().to_string();

    // 5. Wait for SSE to be registered.
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    // 6. Human sends reply via WebSocket.
    let reply_msg = serde_json::json!({
        "event_type": "reply.send",
        "conversation_id": conversation_id,
        "text": "Looks good, ship it!"
    });
    ws_stream
        .send(WsMessage::Text(reply_msg.to_string()))
        .await
        .unwrap();

    // 7. Human receives `reply.delivered` ack.
    let ack = next_json(&mut ws_stream).await;
    assert_eq!(
        ack["event_type"], "reply.delivered",
        "Expected reply.delivered, got: {}",
        ack
    );
    assert_eq!(ack["data"]["delivered"], true);

    // 7b. Close the turn.
    //
    // Multi-turn streaming deliberately keeps the SSE stream open after a
    // text reply — the human may have more to say — so it only terminates
    // on an explicit `end.turn` (or a tool call). Without this the stream
    // never emits [DONE] and the agent blocks forever.
    ws_stream
        .send(WsMessage::Text(
            serde_json::json!({
                "event_type": "end.turn",
                "conversation_id": conversation_id,
            })
            .to_string(),
        ))
        .await
        .unwrap();

    // 8. Agent receives SSE response.
    let resp = agent_task.await.unwrap();
    assert_eq!(resp.status(), 200);
    let body = resp.text().await.unwrap();
    // The reply is split into SSE content chunks (by whitespace),
    // so we check for the presence of the key fragments.
    assert!(body.contains("Looks"), "Missing 'Looks' in SSE: {}", body);
    assert!(body.contains("ship"), "Missing 'ship' in SSE: {}", body);
    assert!(body.contains("it!"), "Missing 'it!' in SSE: {}", body);
    assert!(body.contains("[DONE]"), "Missing [DONE]",);

    let _ = ws_stream.close(None).await;
}

// ════════════════════════════════════════════════════════════
// 2. Human offline → message persisted → reconnect → drain
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn test_human_offline_message_persisted_and_drained_on_reconnect() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let http_client = reqwest::Client::new();

    // 1. Agent sends a streaming request while human is OFFLINE.
    //    The message is stored, SSE is registered, and the agent waits.
    let agent_task = tokio::spawn({
        let client = http_client.clone();
        async move {
            client
                .post(format!("http://{}/v1/chat/completions", addr))
                .header("Authorization", format!("Bearer {}", DEMO_KEY))
                .json(&serde_json::json!({
                    "model": "human",
                    "messages": [
                        {"role": "user", "content": "Are you there?"}
                    ],
                    "stream": true
                }))
                .send()
                .await
                .unwrap()
        }
    });

    // 2. Wait for the agent's message to be stored and SSE registered.
    tokio::time::sleep(std::time::Duration::from_millis(300)).await;

    // 3. Human connects via WebSocket (now online).
    let ws_url = format!("ws://{}/ws?api_key={}", addr, DEMO_KEY);
    let (mut ws_stream, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("WS connect failed");

    // 4. Receive `session.connected`.
    let connected = next_json(&mut ws_stream).await;
    assert_eq!(connected["event_type"], "session.connected");

    // 5. Receive `message.received` — the agent's message pushed
    //    to the now-online human (real-time push, since SSE is still waiting).
    let msg_event = next_json_skip_capability(&mut ws_stream).await;
    assert_eq!(
        msg_event["event_type"], "message.received",
        "Expected message.received, got: {}",
        msg_event
    );
    assert_eq!(msg_event["data"]["text"], "Are you there?");

    let conversation_id = msg_event["conversation_id"].as_str().unwrap().to_string();

    // 6. Human sends reply via WebSocket.
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    let reply_msg = serde_json::json!({
        "event_type": "reply.send",
        "conversation_id": conversation_id,
        "text": "Yes I'm here"
    });
    ws_stream
        .send(WsMessage::Text(reply_msg.to_string()))
        .await
        .unwrap();

    // 7. Receive `reply.delivered` ack.
    let ack = next_json(&mut ws_stream).await;
    assert_eq!(ack["event_type"], "reply.delivered");

    // 7b. Close the turn — see the note in test 1: a text reply alone does
    //     not terminate the SSE stream.
    ws_stream
        .send(WsMessage::Text(
            serde_json::json!({
                "event_type": "end.turn",
                "conversation_id": conversation_id,
            })
            .to_string(),
        ))
        .await
        .unwrap();

    // 8. Agent receives SSE response.
    let resp = agent_task.await.unwrap();
    assert_eq!(resp.status(), 200);
    let body = resp.text().await.unwrap();
    assert!(body.contains("Yes"), "Missing 'Yes' in SSE: {}", body);
    assert!(body.contains("here"), "Missing 'here' in SSE: {}", body);
    assert!(body.contains("[DONE]"), "Missing [DONE]");

    let _ = ws_stream.close(None).await;
}

// ════════════════════════════════════════════════════════════
// 3. Multi-device fanout
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn test_multi_device_fanout() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let ws_url = format!("ws://{}/ws?api_key={}", addr, DEMO_KEY);

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    // 1. Connect device 1 (mobile).
    let (mut ws1, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("WS1 connect failed");
    let _ = next_json(&mut ws1).await; // session.connected

    // 2. Connect device 2 (desktop).
    let (mut ws2, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("WS2 connect failed");
    let _ = next_json(&mut ws2).await; // session.connected

    // 3. Agent sends a message.
    let http_client = reqwest::Client::new();
    let agent_task = tokio::spawn({
        let client = http_client.clone();
        async move {
            client
                .post(format!("http://{}/v1/chat/completions", addr))
                .header("Authorization", format!("Bearer {}", DEMO_KEY))
                .json(&serde_json::json!({
                    "model": "human",
                    "messages": [{"role": "user", "content": "Ping both devices"}],
                    "stream": true
                }))
                .send()
                .await
                .unwrap()
        }
    });

    // 4. Both devices should receive `message.received`.
    let msg1 = next_json_skip_capability(&mut ws1).await;
    assert_eq!(msg1["event_type"], "message.received");
    assert_eq!(msg1["data"]["text"], "Ping both devices");

    let msg2 = next_json_skip_capability(&mut ws2).await;
    assert_eq!(msg2["event_type"], "message.received");
    assert_eq!(msg2["data"]["text"], "Ping both devices");

    // Both should have the same conversation_id.
    assert_eq!(msg1["conversation_id"], msg2["conversation_id"]);

    // 5. Reply from device 1, both get `reply.delivered`.
    let conv_id = msg1["conversation_id"].as_str().unwrap().to_string();

    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    let reply = serde_json::json!({
        "event_type": "reply.send",
        "conversation_id": conv_id,
        "text": "Got it on mobile"
    });
    ws1.send(WsMessage::Text(reply.to_string())).await.unwrap();

    // Device 1 gets reply.delivered.
    let ack1 = next_json(&mut ws1).await;
    assert_eq!(ack1["event_type"], "reply.delivered");

    // Device 2 also gets reply.delivered (fanout).
    let ack2 = next_json(&mut ws2).await;
    assert_eq!(ack2["event_type"], "reply.delivered");

    // 5b. Close the turn — see the note in test 1.
    ws1.send(WsMessage::Text(
        serde_json::json!({
            "event_type": "end.turn",
            "conversation_id": conv_id,
        })
        .to_string(),
    ))
    .await
    .unwrap();

    // 6. Agent gets SSE response.
    let resp = agent_task.await.unwrap();
    assert_eq!(resp.status(), 200);
    let body = resp.text().await.unwrap();
    assert!(body.contains("Got"), "Missing 'Got' in SSE: {}", body);
    assert!(body.contains("mobile"), "Missing 'mobile' in SSE: {}", body);
    assert!(body.contains("[DONE]"), "Missing [DONE]");

    let _ = ws1.close(None).await;
    let _ = ws2.close(None).await;
}

// ════════════════════════════════════════════════════════════
// 4. WebSocket authentication
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn test_ws_valid_key_receives_session_connected() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let ws_url = format!("ws://{}/ws?api_key={}", addr, DEMO_KEY);

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let (mut ws, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("WS connect failed");

    let event = next_json(&mut ws).await;
    assert_eq!(event["event_type"], "session.connected");
    assert_eq!(event["data"]["human_id"], "hum_demo_alice");
    assert_eq!(event["data"]["display_name"], "Alice Chen");

    let _ = ws.close(None).await;
}

#[tokio::test]
async fn test_ws_invalid_key_no_session_connected() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let ws_url = format!("ws://{}/ws?api_key=ohk_invalid", addr);

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let result = tokio_tungstenite::connect_async(&ws_url).await;

    if let Ok((mut ws, _)) = result {
        let msg = ws.next().await;
        if let Some(Ok(WsMessage::Text(text))) = msg {
            let json: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
            assert_ne!(
                json.get("event_type").and_then(|v| v.as_str()),
                Some("session.connected")
            );
        }
    }
}

#[tokio::test]
async fn test_ws_missing_key_no_session_connected() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let ws_url = format!("ws://{}/ws", addr);

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let result = tokio_tungstenite::connect_async(&ws_url).await;

    if let Ok((mut ws, _)) = result {
        let msg = ws.next().await;
        if let Some(Ok(WsMessage::Text(text))) = msg {
            let json: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
            assert_ne!(
                json.get("event_type").and_then(|v| v.as_str()),
                Some("session.connected")
            );
        }
    }
}
