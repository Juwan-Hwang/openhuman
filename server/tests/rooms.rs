//! Integration tests: group rooms (design doc §13.1).
//!
//! Backend is selected like main.rs: memory by default, postgres when
//! `OPENHUMAN_BACKEND=postgres` and `DATABASE_URL` are set (the §13.2
//! postgres cell, mirroring postgres_compat.rs). Timings are shortened
//! via env (`OPENHUMAN_ROOM_SEGMENT_MAX_SECS=2`) and per-room metadata.

use openhuman_server::build_router;
use openhuman_server::model::identity::{ApiKey, HumanIdentity, KeyScope};
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::traits::IdentityRepository;
use openhuman_server::storage::AppState;

use futures::stream::StreamExt;
use futures::SinkExt;
use tokio_tungstenite::tungstenite::Message as WsMessage;

const DEMO_KEY: &str = "ohk_demo_alice_codex"; // Alice, the owner in these tests

fn setup() {
    // Process-global flag; every rooms test wants it on, other suites are
    // unaffected (the flag only registers extra routes).
    std::env::set_var("OPENHUMAN_ROOMS", "1");
    std::env::set_var("OPENHUMAN_ROOM_SEGMENT_MAX_SECS", "2");
    std::env::set_var("OPENHUMAN_ROOM_SEGMENT_QUIET_SECS", "1");
}

async fn app_with_humans(extra: &[&str]) -> (axum::Router, std::net::SocketAddr) {
    setup();
    // §13.2 postgres cell: same suite against a live database. Inserts
    // below are ON CONFLICT idempotent and every test uses fresh room ids,
    // so parallel tests sharing one database are safe. OPENHUMAN_DEMO=1
    // keeps the seeded demo key live — migrate() revokes it otherwise.
    if std::env::var("OPENHUMAN_BACKEND").ok().as_deref() == Some("postgres") {
        std::env::set_var("OPENHUMAN_DEMO", "1");
        let url = std::env::var("DATABASE_URL").expect("DATABASE_URL (postgres rooms cell)");
        let store = openhuman_server::storage::postgres::PostgresStore::new(&url)
            .await
            .expect("connect postgres");
        store.migrate().await.expect("migrations 001-007 apply");
        seed_extra_humans(&store, extra).await;
        // Same split as main.rs: PostgresStore for persistence plus an
        // in-memory reply registry for the reply channels.
        let reply = openhuman_server::storage::postgres::InMemoryReplyRegistry::new();
        return serve(AppState::from_postgres(store, reply)).await;
    }
    let store = MemoryStore::seeded();
    seed_extra_humans(&store, extra).await;
    serve(AppState::from_store(store)).await
}

/// The extra humans/agents/responder keys a test asks for, shared by both
/// backends. `S: IdentityRepository` covers MemoryStore and PostgresStore.
async fn seed_extra_humans<S: IdentityRepository>(store: &S, extra: &[&str]) {
    for (i, name) in extra.iter().enumerate() {
        let hid = format!("hum_test_{}", name);
        let key = format!("ohk_test_{}", name);
        store
            .insert_human(HumanIdentity {
                id: hid.clone(),
                display_name: name.to_string(),
                avatar_url: None,
                status: None,
                capabilities: vec![],
                metadata: Default::default(),
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
            })
            .await;
        // A responder key: the human side of rooms (management API + WS).
        let aid = format!("agt_test_{}", i);
        store
            .insert_agent(openhuman_server::model::identity::AgentIdentity {
                id: aid.clone(),
                name: format!("{} seat", name),
                client_type: openhuman_server::model::identity::ClientType::Custom,
                api_key_id: format!("key_test_{}", i),
                capabilities: vec![],
                metadata: Default::default(),
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
            })
            .await;
        store
            .insert_api_key(
                ApiKey::new(format!("key_test_{}", i), &key, aid, hid)
                    .with_scope(KeyScope::Responder),
            )
            .await;
    }
}

/// Bind the router on an ephemeral port and serve it in the background.
async fn serve(state: AppState) -> (axum::Router, std::net::SocketAddr) {
    let app = build_router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    (app_unused(), addr)
}

// The router is moved into the server task; tests talk over HTTP only.
fn app_unused() -> axum::Router {
    build_router(AppState::from_store(MemoryStore::new()))
}

fn http() -> reqwest::Client {
    reqwest::Client::new()
}

async fn create_room(addr: &std::net::SocketAddr, key: &str, name: &str) -> String {
    let res = http()
        .post(format!("http://{}/v1/rooms", addr))
        .bearer_auth(key)
        .json(&serde_json::json!({"name": name}))
        .send()
        .await
        .unwrap();
    let status = res.status();
    let text = res.text().await.unwrap();
    assert_eq!(status, 201, "create room: {}", text);
    let body: serde_json::Value = serde_json::from_str(&text).unwrap();
    body["id"].as_str().unwrap().to_string()
}

async fn mint_caller_key(
    addr: &std::net::SocketAddr,
    owner_key: &str,
    room: &str,
    display: &str,
) -> String {
    let res = http()
        .post(format!("http://{}/v1/rooms/{}/caller-keys", addr, room))
        .bearer_auth(owner_key)
        .json(&serde_json::json!({"display_name": display}))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 201);
    let body: serde_json::Value = res.json().await.unwrap();
    body["api_key"].as_str().unwrap().to_string()
}

async fn room_log(addr: &std::net::SocketAddr, key: &str, room: &str) -> Vec<serde_json::Value> {
    let res = http()
        .get(format!("http://{}/v1/rooms/{}/messages", addr, room))
        .bearer_auth(key)
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let body: serde_json::Value = res.json().await.unwrap();
    body["messages"].as_array().unwrap().clone()
}

// ════════════════════════════════════════════════════════════
// Management + authz
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn create_list_detail_and_key_binding() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "测试群").await;

    // Detail: owner is listed with role owner.
    let res = http()
        .get(format!("http://{}/v1/rooms/{}", addr, room))
        .bearer_auth(DEMO_KEY)
        .send()
        .await
        .unwrap();
    let body: serde_json::Value = res.json().await.unwrap();
    assert_eq!(body["members"][0]["role"], "owner");

    let room_key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Claude Code").await;

    // Unbound caller-capable key on the room ingress → 403.
    let res = http()
        .post(format!(
            "http://{}/rooms/{}/v1/chat/completions",
            addr, room
        ))
        .bearer_auth(DEMO_KEY)
        .json(&serde_json::json!({"model":"测试群","messages":[{"role":"user","content":"hi"}]}))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 403);

    // Room-bound key on the plain ingress → 403.
    let res = http()
        .post(format!("http://{}/v1/chat/completions", addr))
        .bearer_auth(&room_key)
        .json(&serde_json::json!({"model":"x","messages":[{"role":"user","content":"hi"}]}))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 403);

    // A caller-scoped room key cannot manage rooms (responder side).
    let res = http()
        .get(format!("http://{}/v1/rooms", addr))
        .bearer_auth(&room_key)
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 403);

    // Per-room models endpoint answers the room name; alias works too.
    let res = http()
        .get(format!("http://{}/rooms/{}/v1/v1/models", addr, room))
        .bearer_auth(&room_key)
        .send()
        .await
        .unwrap();
    let body: serde_json::Value = res.json().await.unwrap();
    assert_eq!(body["data"][0]["id"], "测试群");
}

// ════════════════════════════════════════════════════════════
// Invites
// ════════════════════════════════════════════════════════════

async fn mint_invite(addr: &std::net::SocketAddr, owner_key: &str, room: &str) -> String {
    let res = http()
        .post(format!("http://{}/v1/rooms/{}/invites", addr, room))
        .bearer_auth(owner_key)
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 201);
    let body: serde_json::Value = res.json().await.unwrap();
    body["code"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn invite_accept_rejoin_revoke_unknown() {
    let (_app, addr) = app_with_humans(&["bob"]).await;
    let room = create_room(&addr, DEMO_KEY, "邀请测试").await;
    let code = mint_invite(&addr, DEMO_KEY, &room).await;
    assert_eq!(code.len(), 32, "128-bit hex code");

    // Accept: 201 first time.
    let res = http()
        .post(format!("http://{}/v1/invites/{}/accept", addr, code))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 201);

    // Rejoin is idempotent: 200, no duplicate member.
    let res = http()
        .post(format!("http://{}/v1/invites/{}/accept", addr, code))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let body: serde_json::Value = res.json().await.unwrap();
    assert_eq!(body["member_count"], 2);

    // Unknown code → 404.
    let res = http()
        .post(format!(
            "http://{}/v1/invites/{}/accept",
            addr,
            "f".repeat(32)
        ))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 404);

    // Revoke (owner only) → accept 410.
    let res = http()
        .delete(format!(
            "http://{}/v1/rooms/{}/invites/{}",
            addr, room, code
        ))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 403, "members cannot revoke");
    let res = http()
        .delete(format!(
            "http://{}/v1/rooms/{}/invites/{}",
            addr, room, code
        ))
        .bearer_auth(DEMO_KEY)
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let res = http()
        .post(format!("http://{}/v1/invites/{}/accept", addr, code))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();
    // The code is dead: 410, even for someone already in the room (his
    // membership itself is unaffected).
    assert_eq!(res.status(), 410);
}

#[tokio::test]
async fn room_cap_ten_members() {
    let names: Vec<String> = (0..10).map(|i| format!("m{}", i)).collect();
    let refs: Vec<&str> = names.iter().map(|s| s.as_str()).collect();
    let (_app, addr) = app_with_humans(&refs).await;
    let room = create_room(&addr, DEMO_KEY, "满员测试").await;
    let code = mint_invite(&addr, DEMO_KEY, &room).await;

    // Owner + 9 = 10 seats; the 10th joiner (index 9) overflows.
    for (i, name) in names.iter().enumerate() {
        let res = http()
            .post(format!("http://{}/v1/invites/{}/accept", addr, code))
            .header("x-forwarded-for", format!("10.9.0.{}", i + 1))
            .bearer_auth(format!("ohk_test_{}", name))
            .send()
            .await
            .unwrap();
        if i < 9 {
            assert_eq!(res.status(), 201, "join {} should fit", i);
        } else {
            assert_eq!(res.status(), 409, "room must cap at 10 members");
        }
    }
}

// ════════════════════════════════════════════════════════════
// Kick / leave / visibility
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn kick_blocks_after_seq_and_owner_is_protected() {
    let (_app, addr) = app_with_humans(&["bob"]).await;
    let room = create_room(&addr, DEMO_KEY, "踢人测试").await;
    let code = mint_invite(&addr, DEMO_KEY, &room).await;
    http()
        .post(format!("http://{}/v1/invites/{}/accept", addr, code))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();

    // The owner cannot be kicked.
    let res = http()
        .delete(format!(
            "http://{}/v1/rooms/{}/members/hum_demo_alice",
            addr, room
        ))
        .bearer_auth(DEMO_KEY)
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 409);

    // Kick bob → his after_seq reads are 403 from then on.
    let res = http()
        .delete(format!(
            "http://{}/v1/rooms/{}/members/hum_test_bob",
            addr, room
        ))
        .bearer_auth(DEMO_KEY)
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let res = http()
        .get(format!("http://{}/v1/rooms/{}/messages", addr, room))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 403);
}

// ════════════════════════════════════════════════════════════
// Ingress: segments, keepalive, dedup, cursor
// ════════════════════════════════════════════════════════════

/// Collect a full non-streaming segment response.
async fn segment(
    addr: &std::net::SocketAddr,
    room: &str,
    key: &str,
    messages: serde_json::Value,
    tools: serde_json::Value,
) -> serde_json::Value {
    let res = http()
        .post(format!(
            "http://{}/rooms/{}/v1/chat/completions",
            addr, room
        ))
        .bearer_auth(key)
        .json(&serde_json::json!({
            "model": "room", "stream": false,
            "messages": messages, "tools": tools,
        }))
        .send()
        .await
        .unwrap();
    let status = res.status();
    let text = res.text().await.unwrap();
    assert_eq!(status, 200, "segment: {}", text);
    serde_json::from_str(&text).unwrap()
}

#[tokio::test]
async fn segment_closes_with_keepalive_call_and_result_is_dropped() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "分段测试").await;
    let key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Codex").await;

    // Declared whitelist tool: the close must borrow get_goal with {} args.
    let tools = serde_json::json!([
        {"type":"function","function":{"name":"get_goal","description":"g","parameters":{}}},
        {"type":"function","function":{"name":"Bash","description":"b","parameters":{}}}
    ]);
    let r = segment(
        &addr,
        &room,
        &key,
        serde_json::json!([{"role":"user","content":"第一句"}]),
        tools.clone(),
    )
    .await;
    let call = &r["choices"][0]["message"]["tool_calls"][0];
    assert_eq!(r["choices"][0]["finish_reason"], "tool_calls");
    assert_eq!(call["function"]["name"], "get_goal");
    assert_eq!(call["function"]["arguments"], "{}");
    let call_id = call["id"].as_str().unwrap().to_string();
    assert!(call_id.starts_with("ohka_"));

    // Caller speech landed in the log with its display name.
    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 1);
    // §10.2: caller speech carries its short session tag in the name.
    assert!(log[0]["sender_name"]
        .as_str()
        .unwrap()
        .starts_with("小明的 Codex · "));

    // Next segment carries the keepalive result back: dropped on sight.
    let r2 = segment(
        &addr, &room, &key,
        serde_json::json!([
            {"role":"user","content":"第一句"},
            {"role":"assistant","content":null,"tool_calls":[{"id":call_id,"type":"function","function":{"name":"get_goal","arguments":"{}"}}]},
            {"role":"tool","tool_call_id":call_id,"content":"{\"goal\":null}"}
        ]),
        tools.clone(),
    )
    .await;
    assert_eq!(r2["choices"][0]["finish_reason"], "tool_calls");
    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 1, "keepalive result never enters the log");

    // Pairing fallback: the client rewrote the id; the result answers a
    // whitelisted tool with {} args — still dropped.
    let r3 = segment(
        &addr, &room, &key,
        serde_json::json!([
            {"role":"user","content":"第一句"},
            {"role":"assistant","content":null,"tool_calls":[{"id":"call_rewritten_1","type":"function","function":{"name":"get_goal","arguments":"{}"}}]},
            {"role":"tool","tool_call_id":"call_rewritten_1","content":"{\"goal\":null}"}
        ]),
        tools,
    )
    .await;
    assert_eq!(r3["choices"][0]["finish_reason"], "tool_calls");
    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 1, "rewritten keepalive result also dropped");
}

#[tokio::test]
async fn interjection_leadin_is_stripped() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "插话测试").await;
    let key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Claude Code").await;

    segment(
        &addr,
        &room,
        &key,
        serde_json::json!([{"role":"user","content":
            "The user sent a new message while you were working:\n先停一下，看看这个"}]),
        serde_json::json!([]),
    )
    .await;
    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 1);
    assert_eq!(log[0]["text"], "先停一下，看看这个");
}

#[tokio::test]
async fn resend_is_deduped_and_new_triple_skips_history() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "去重测试").await;
    let key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Codex").await;

    // Same request twice (client retry): one log entry.
    for _ in 0..2 {
        segment(
            &addr,
            &room,
            &key,
            serde_json::json!([{"role":"user","content":"重复检测"}]),
            serde_json::json!([]),
        )
        .await;
    }
    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 1, "a retried request must not double-log");

    // A different session (new window): cursor starts at the tip, so the
    // response streams nothing from before — it closes empty.
    let r = segment(
        &addr,
        &room,
        &key,
        serde_json::json!([{"role":"user","content":"另一个窗口"}]),
        serde_json::json!([]),
    )
    .await;
    // The new-triple response itself closes via keepalive with no backlog
    // content — only the caller's own new line is in the log.
    assert_eq!(r["choices"][0]["finish_reason"], "tool_calls");
    let content = r["choices"][0]["message"]["content"].as_str().unwrap_or("");
    assert!(
        !content.contains("重复检测"),
        "new session must not replay history"
    );
}

// ════════════════════════════════════════════════════════════
// Live flow: member speech, prefixes, owner end.turn
// ════════════════════════════════════════════════════════════

async fn ws_connect(
    addr: &std::net::SocketAddr,
    key: &str,
) -> tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>> {
    let url = format!("ws://{}/ws?api_key={}", addr, key);
    let (ws, _) = tokio_tungstenite::connect_async(url).await.unwrap();
    ws
}

async fn ws_next(
    ws: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> serde_json::Value {
    loop {
        match ws.next().await {
            Some(Ok(WsMessage::Text(t))) => return serde_json::from_str(&t).unwrap(),
            Some(Ok(WsMessage::Ping(_))) | Some(Ok(WsMessage::Pong(_))) => continue,
            other => panic!("ws: {:?}", other),
        }
    }
}

/// Read SSE data lines until `finish` matches or timeout; returns all JSON chunks.
async fn sse_collect(
    res: reqwest::Response,
    until: &str,
    timeout: std::time::Duration,
) -> Vec<serde_json::Value> {
    let mut out = Vec::new();
    let mut stream = res.bytes_stream();
    let mut buf = String::new();
    let deadline = tokio::time::Instant::now() + timeout;
    loop {
        let next = tokio::time::timeout_at(deadline, stream.next()).await;
        match next {
            Ok(Some(Ok(bytes))) => {
                buf.push_str(&String::from_utf8_lossy(&bytes));
                while let Some(pos) = buf.find("\n\n") {
                    let frame = buf[..pos].to_string();
                    buf = buf[pos + 2..].to_string();
                    for line in frame.lines() {
                        if let Some(data) = line.strip_prefix("data: ") {
                            if data == "[DONE]" {
                                return out;
                            }
                            if let Ok(v) = serde_json::from_str::<serde_json::Value>(data) {
                                let is_end =
                                    v["choices"][0]["finish_reason"].as_str() == Some(until);
                                out.push(v);
                                if is_end {
                                    return out;
                                }
                            }
                        }
                    }
                }
            }
            _ => return out,
        }
    }
}

#[tokio::test]
async fn member_speech_streams_with_prefix_and_owner_ends_turn() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "直播测试").await;
    let key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Claude Code").await;

    // Caller opens a stream (segmented, quiet close = 1s, max = 2s).
    let req = http()
        .post(format!(
            "http://{}/rooms/{}/v1/chat/completions",
            addr, room
        ))
        .bearer_auth(&key)
        .json(&serde_json::json!({
            "model": "直播测试", "stream": true,
            "messages": [{"role":"user","content":"有人吗"}],
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(req.status(), 200);

    // Owner speaks over WS.
    let mut ws = ws_connect(&addr, DEMO_KEY).await;
    let _hello = ws_next(&mut ws).await; // session.connected
    ws.send(WsMessage::Text(
        serde_json::json!({"event_type":"reply.send","conversation_id":room,"text":"我在，说吧"})
            .to_string(),
    ))
    .await
    .unwrap();

    let chunks = sse_collect(req, "tool_calls", std::time::Duration::from_secs(10)).await;
    let text: String = chunks
        .iter()
        .filter_map(|c| c["choices"][0]["delta"]["content"].as_str())
        .collect();
    assert!(
        text.contains("[Alice Chen] 我在，说吧"),
        "streamed with speaker prefix, got: {}",
        text
    );
    // Content flowed → the quiet clock (1s) closed the segment with a
    // keepalive call, not a bare stop.
    let last = chunks.last().unwrap();
    assert_eq!(last["choices"][0]["finish_reason"], "tool_calls");
    let call_id = chunks
        .iter()
        .filter_map(|c| c["choices"][0]["delta"]["tool_calls"][0]["id"].as_str())
        .next()
        .unwrap_or("")
        .to_string();
    assert!(call_id.starts_with("ohka_"));

    // Next segment: owner end.turn closes it with stop.
    let req = http()
        .post(format!("http://{}/rooms/{}/v1/chat/completions", addr, room))
        .bearer_auth(&key)
        .json(&serde_json::json!({
            "model": "直播测试", "stream": true,
            "messages": [
                {"role":"user","content":"有人吗"},
                {"role":"assistant","content":null,"tool_calls":[{"id":call_id,"type":"function","function":{"name":"ohka_noop","arguments":"{}"}}]},
                {"role":"tool","tool_call_id":call_id,"content":"done"}
            ],
        }))
        .send()
        .await
        .unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    ws.send(WsMessage::Text(
        serde_json::json!({"event_type":"end.turn","conversation_id":room}).to_string(),
    ))
    .await
    .unwrap();
    let chunks = sse_collect(req, "stop", std::time::Duration::from_secs(5)).await;
    let last = chunks.last().unwrap();
    assert_eq!(last["choices"][0]["finish_reason"], "stop");
    // The keepalive result from the previous segment never entered the log.
    let log = room_log(&addr, DEMO_KEY, &room).await;
    let texts: Vec<&str> = log.iter().filter_map(|m| m["text"].as_str()).collect();
    assert_eq!(texts, vec!["有人吗", "我在，说吧"]);
}

#[tokio::test]
async fn non_owner_end_turn_is_rejected() {
    let (_app, addr) = app_with_humans(&["bob"]).await;
    let room = create_room(&addr, DEMO_KEY, "权限测试").await;
    let code = mint_invite(&addr, DEMO_KEY, &room).await;
    http()
        .post(format!("http://{}/v1/invites/{}/accept", addr, code))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();

    let mut ws = ws_connect(&addr, "ohk_test_bob").await;
    let _ = ws_next(&mut ws).await; // session.connected
    ws.send(WsMessage::Text(
        serde_json::json!({"event_type":"end.turn","conversation_id":room}).to_string(),
    ))
    .await
    .unwrap();
    let ev = ws_next(&mut ws).await;
    assert_eq!(ev["event_type"], "error");
    assert_eq!(ev["data"]["code"], "owner_only");

    // Same for tool.invoke.
    ws.send(WsMessage::Text(
        serde_json::json!({"event_type":"tool.invoke","conversation_id":room,"invocation_id":"inv_1","tool_id":"Bash","input":{}})
            .to_string(),
    ))
    .await
    .unwrap();
    let ev = ws_next(&mut ws).await;
    assert_eq!(ev["data"]["code"], "owner_only");
}

// ════════════════════════════════════════════════════════════
// Aux requests + owner leave
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn auxiliary_request_bypasses_room_log() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "辅助测试").await;
    let key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Codex").await;

    // A title-generation style request: system prompt about titles,
    // user-only, no tools — auxiliary, auto-answered, nothing in the log.
    let res = http()
        .post(format!(
            "http://{}/rooms/{}/v1/chat/completions",
            addr, room
        ))
        .bearer_auth(&key)
        .json(&serde_json::json!({
            "model": "room", "stream": false,
            "messages": [
                {"role":"system","content":"Generate a short title for this conversation."},
                {"role":"user","content":"hello world"}
            ],
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 0, "aux requests never touch the room log");
}

#[tokio::test]
async fn owner_leave_revokes_room_keys() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "退群测试").await;
    let key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Codex").await;

    let res = http()
        .post(format!("http://{}/v1/rooms/{}/leave", addr, room))
        .bearer_auth(DEMO_KEY)
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 200);

    // The room key is revoked with the owner's departure.
    let res = http()
        .post(format!(
            "http://{}/rooms/{}/v1/chat/completions",
            addr, room
        ))
        .bearer_auth(&key)
        .json(&serde_json::json!({"model":"x","messages":[{"role":"user","content":"hi"}]}))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 403, "revoked room key is forbidden");
}

// ════════════════════════════════════════════════════════════
// Protocol lines: Anthropic Messages + OpenAI Responses (§5.2)
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn anthropic_room_line_segments_like_chat() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "Claude线测试").await;
    let key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Claude Code").await;

    // Unbound key: 403 on the Anthropic room line too.
    let res = http()
        .post(format!("http://{}/rooms/{}/v1/messages", addr, room))
        .bearer_auth(DEMO_KEY)
        .json(&serde_json::json!({"model":"claude","max_tokens":64,"messages":[{"role":"user","content":"hi"}]}))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 403);

    // Room key: a quiet segment closes as an Anthropic tool_use turn.
    let res = http()
        .post(format!("http://{}/rooms/{}/v1/messages", addr, room))
        .bearer_auth(&key)
        .json(&serde_json::json!({
            "model": "claude", "max_tokens": 64,
            "tools": [{"name":"get_goal","description":"g","input_schema":{"type":"object","properties":{}}}],
            "messages": [{"role":"user","content":"来自Claude"}],
        }))
        .send()
        .await
        .unwrap();
    let status = res.status();
    let text = res.text().await.unwrap();
    assert_eq!(status, 200, "anthropic room line: {}", text);
    let body: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(body["stop_reason"], "tool_use");
    let block = &body["content"][0];
    assert_eq!(block["type"], "tool_use");
    assert_eq!(block["name"], "get_goal");
    assert!(block["id"].as_str().unwrap().starts_with("ohka_"));

    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 1);
    assert_eq!(log[0]["text"], "来自Claude");
    assert!(log[0]["sender_name"]
        .as_str()
        .unwrap()
        .starts_with("小明的 Claude Code · "));
}

#[tokio::test]
async fn responses_room_line_segments_like_chat() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "Codex线测试").await;
    let key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Codex").await;

    let res = http()
        .post(format!("http://{}/rooms/{}/v1/responses", addr, room))
        .bearer_auth(&key)
        .json(&serde_json::json!({
            "model": "gpt", "stream": false,
            "tools": [{"type":"function","name":"list_bash","description":"b","parameters":{"type":"object","properties":{}}}],
            "input": "来自Codex",
        }))
        .send()
        .await
        .unwrap();
    let status = res.status();
    let text = res.text().await.unwrap();
    assert_eq!(status, 200, "responses room line: {}", text);
    let body: serde_json::Value = serde_json::from_str(&text).unwrap();
    let call = body["output"]
        .as_array()
        .unwrap()
        .iter()
        .find(|o| o["type"] == "function_call")
        .expect("a function_call item closes the segment");
    assert_eq!(call["name"], "list_bash");
    assert_eq!(call["arguments"], "{}");

    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 1);
    assert_eq!(log[0]["text"], "来自Codex");
}

// ════════════════════════════════════════════════════════════
// Async mode: 202 + poll, room cursor rides the segment (§5.3)
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn async_mode_polls_a_room_segment() {
    let (_app, addr) = app_with_humans(&[]).await;
    let room = create_room(&addr, DEMO_KEY, "异步测试").await;
    let key = mint_caller_key(&addr, DEMO_KEY, &room, "小明的 Codex").await;

    let res = http()
        .post(format!(
            "http://{}/rooms/{}/v1/chat/completions",
            addr, room
        ))
        .bearer_auth(&key)
        .header("x-openhuman-mode", "async")
        .json(&serde_json::json!({
            "model": "room", "messages": [{"role":"user","content":"异步第一句"}],
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 202);
    let ack: serde_json::Value = res.json().await.unwrap();
    let invocation = ack["id"].as_str().unwrap().to_string();
    assert_eq!(ack["source"], "room_segment");

    // The plain poll path refuses a room-bound key (binding holds).
    let res = http()
        .get(format!("http://{}/v1/replies/{}", addr, invocation))
        .bearer_auth(&key)
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 403);

    // Long-poll until the quiet close completes the segment.
    let res = http()
        .get(format!(
            "http://{}/rooms/{}/v1/replies/{}?wait=10",
            addr, room, invocation
        ))
        .bearer_auth(&key)
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let reply: serde_json::Value = res.json().await.unwrap();
    assert_eq!(
        reply["choices"][0]["finish_reason"], "tool_calls",
        "the polled segment closes with the keepalive call: {}",
        reply
    );

    // Caller speech still landed in the room log.
    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 1);
    assert_eq!(log[0]["text"], "异步第一句");
}

// ════════════════════════════════════════════════════════════
// New-member visibility watermark, on both read paths (§4.4)
// ════════════════════════════════════════════════════════════

#[tokio::test]
async fn new_member_cannot_read_prejoin_history() {
    let (_app, addr) = app_with_humans(&["bob"]).await;
    let room = create_room(&addr, DEMO_KEY, "可见性测试").await;

    // Owner speaks before bob joins.
    let mut ws = ws_connect(&addr, DEMO_KEY).await;
    let _ = ws_next(&mut ws).await; // session.connected
    ws.send(WsMessage::Text(
        serde_json::json!({"event_type":"reply.send","conversation_id":room,"text":"加入前的秘密"})
            .to_string(),
    ))
    .await
    .unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(400)).await;

    // Bob joins; the watermark is set at accept time.
    let code = mint_invite(&addr, DEMO_KEY, &room).await;
    http()
        .post(format!("http://{}/v1/invites/{}/accept", addr, code))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();

    // Owner speaks again — this one is visible to bob.
    ws.send(WsMessage::Text(
        serde_json::json!({"event_type":"reply.send","conversation_id":room,"text":"加入后的招呼"})
            .to_string(),
    ))
    .await
    .unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(400)).await;

    // Room log endpoint: bob sees only the post-join line.
    let log = room_log(&addr, "ohk_test_bob", &room).await;
    let texts: Vec<&str> = log.iter().filter_map(|m| m["text"].as_str()).collect();
    assert_eq!(texts, vec!["加入后的招呼"]);

    // The generic history endpoint (what the Flutter client reads) applies
    // the same watermark.
    let res = http()
        .get(format!(
            "http://{}/v1/conversations/{}/messages",
            addr, room
        ))
        .bearer_auth("ohk_test_bob")
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let body: serde_json::Value = res.json().await.unwrap();
    let texts: Vec<&str> = body["data"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|m| m["text"].as_str())
        .collect();
    assert_eq!(texts, vec!["加入后的招呼"]);

    // The owner still sees everything on both paths.
    let log = room_log(&addr, DEMO_KEY, &room).await;
    assert_eq!(log.len(), 2);
    let res = http()
        .get(format!(
            "http://{}/v1/conversations/{}/messages",
            addr, room
        ))
        .bearer_auth(DEMO_KEY)
        .send()
        .await
        .unwrap();
    let body: serde_json::Value = res.json().await.unwrap();
    assert_eq!(body["data"].as_array().unwrap().len(), 2);
}
