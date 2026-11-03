//! End-to-end smoke: a scripted seat answers through the real seat API
//! (`GET /v1/seat/inbox`, `POST /v1/seat/reply`) while a client drives
//! the OpenAI-shaped endpoints. Covers chat, images, audio
//! (transcription), batches, assistants, agents (owner/type isolation +
//! task -> result round trip), videos, chatkit, evals (local + seat
//! graders), moderations and decisions: task card -> seat reply ->
//! client gets the result. The seat is a script; no real human is
//! involved anywhere in this file.

use std::collections::{HashMap, HashSet};

use openhuman_server::build_router;
use openhuman_server::model::identity::{AgentIdentity, ClientType, HumanIdentity};
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::AppState;
use serde_json::{json, Value};

const KEY: &str = "ohk_demo_alice_codex";
/// A second principal, added on top of the demo seed, so the owner
/// isolation checks have someone else to be.
const KEY2: &str = "ohk_demo_bob_executor";

async fn spawn_app(app: axum::Router) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
}

async fn spawn_server() -> String {
    let store = MemoryStore::seeded();
    let now = chrono::Utc::now();
    store
        .add_seeded_identity(
            HumanIdentity {
                id: "hum_demo_bob".into(),
                display_name: "Bob Stone".into(),
                avatar_url: None,
                status: None,
                capabilities: Vec::new(),
                metadata: HashMap::new(),
                created_at: now,
                updated_at: now,
            },
            AgentIdentity {
                id: "agt_demo_bob_executor".into(),
                name: "Bob Executor".into(),
                client_type: ClientType::Codex,
                api_key_id: "key_demo_002".into(),
                capabilities: Vec::new(),
                metadata: HashMap::new(),
                created_at: now,
                updated_at: now,
            },
            "key_demo_002",
            KEY2,
        )
        .await;
    spawn_app(build_router(AppState::from_store(store))).await
}

fn auth() -> String {
    format!("Bearer {KEY}")
}

fn auth2() -> String {
    format!("Bearer {KEY2}")
}

/// Every conversation_id mentioned anywhere in an inbox response.
fn all_convs(v: &Value, out: &mut Vec<String>) {
    match v {
        Value::Object(m) => {
            if let Some(Value::String(s)) = m.get("conversation_id") {
                out.push(s.clone());
            }
            for x in m.values() {
                all_convs(x, out);
            }
        }
        Value::Array(a) => {
            for x in a {
                all_convs(x, out);
            }
        }
        _ => {}
    }
}

/// Conversations the seat has not answered yet.
async fn waiting_convs(client: &reqwest::Client, base: &str) -> Vec<String> {
    let r: Value = client
        .get(format!("{base}/v1/seat/inbox?wait=1"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let mut convs = Vec::new();
    all_convs(&r, &mut convs);
    convs.sort();
    convs.dedup();
    convs
}

async fn seat_reply(client: &reqwest::Client, base: &str, conv: &str, body: Value) {
    let mut b = json!({
        "conversation_id": conv,
        "end_turn": true,
        "client_msg_id": format!("smoke{}", uuid::Uuid::new_v4().simple()),
    });
    if let (Some(a), Some(v)) = (b.as_object_mut(), body.as_object()) {
        for (k, x) in v {
            a.insert(k.clone(), x.clone());
        }
    }
    let r = client
        .post(format!("{base}/v1/seat/reply"))
        .header("Authorization", auth())
        .json(&b)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 200, "seat reply: {:?}", r.text().await);
}

/// A tiny valid PNG (1x1).
fn tiny_png_b64() -> String {
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGJgAQAAAP//AwAABgAFV7+r1AAAAABJRU5ErkJggg==".to_string()
}

/// Drive the seat until `request` resolves: answer every new waiting
/// conversation with `answer`.
async fn with_seat<T>(
    client: &reqwest::Client,
    base: &str,
    baseline: HashSet<String>,
    request: tokio::task::JoinHandle<T>,
    answer: Value,
) -> T {
    let request = request;
    // Conversations waiting before this scenario are leftovers from the
    // previous one; never answer them twice (a chat conversation rejects
    // attachments, an answered task is gone anyway).
    let mut answered: HashSet<String> = baseline;
    loop {
        if request.is_finished() {
            break request.await.unwrap();
        }
        for conv in waiting_convs(client, base).await {
            if answered.insert(conv.clone()) {
                seat_reply(client, base, &conv, answer.clone()).await;
            }
        }
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
    }
}

async fn e2e_chat_answer_roundtrip(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_chat_answer_roundtrip start");
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let (b, c) = (base.to_string(), client.clone());
    let req = tokio::spawn(async move {
        c.post(format!("{b}/v1/chat/completions"))
            .header("Authorization", auth())
            .json(&json!({"model": "openhuman-human", "messages": [{"role": "user", "content": "hello seat"}], "stream": false}))
            .send()
            .await
            .unwrap()
    });
    let resp = with_seat(
        client,
        base,
        baseline,
        req,
        json!({"text": "hi from the seat"}),
    )
    .await;
    assert_eq!(resp.status().as_u16(), 200);
    let v: Value = resp.json().await.unwrap();
    assert_eq!(
        v.pointer("/choices/0/message/content")
            .and_then(|c| c.as_str())
            .unwrap_or(""),
        "hi from the seat",
        "chat answer: {v}"
    );
}

async fn e2e_image_generation_with_attachment(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_image_generation_with_attachment start");
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let (b, c) = (base.to_string(), client.clone());
    let req = tokio::spawn(async move {
        c.post(format!("{b}/v1/images/generations"))
            .header("Authorization", auth())
            .json(&json!({"model": "gpt-image-1", "prompt": "a red dot", "size": "1024x1024"}))
            .send()
            .await
            .unwrap()
    });
    let png = tiny_png_b64();
    let resp = with_seat(
        client,
        base,
        baseline,
        req,
        json!({"text": "", "attachments": [{"name": "dot.png", "mime": "image/png", "data": png}]}),
    )
    .await;
    assert_eq!(resp.status().as_u16(), 200);
    let v: Value = resp.json().await.unwrap();
    let d0 = &v["data"][0];
    assert!(
        d0.get("b64_json").is_some() || d0.get("url").is_some(),
        "image result: {v}"
    );
}

async fn e2e_audio_transcription_text_answer(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_audio_transcription_text_answer start");
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let part = reqwest::multipart::Part::bytes(b"FAKEM4AAUDIO".to_vec())
        .file_name("clip.m4a")
        .mime_str("audio/mp4")
        .unwrap();
    let form = reqwest::multipart::Form::new()
        .text("model", "whisper-1")
        .part("file", part);
    let (b, c) = (base.to_string(), client.clone());
    let req = tokio::spawn(async move {
        c.post(format!("{b}/v1/audio/transcriptions"))
            .header("Authorization", auth())
            .multipart(form)
            .send()
            .await
            .unwrap()
    });
    let resp = with_seat(
        client,
        base,
        baseline,
        req,
        json!({"text": "a transcript from the seat"}),
    )
    .await;
    assert_eq!(resp.status().as_u16(), 200);
    let v: Value = resp.json().await.unwrap();
    assert_eq!(
        v["text"].as_str().unwrap_or(""),
        "a transcript from the seat",
        "transcription: {v}"
    );
}

async fn e2e_batch_two_lines_complete(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_batch_two_lines_complete start");
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    // The batch input file: two chat completion lines.
    let lines = concat!(
        r#"{"custom_id": "a", "method": "POST", "url": "/v1/chat/completions", "body": {"model": "openhuman-human", "messages": [{"role": "user", "content": "line a"}]}}"#,
        "\n",
        r#"{"custom_id": "b", "method": "POST", "url": "/v1/chat/completions", "body": {"model": "openhuman-human", "messages": [{"role": "user", "content": "line b"}]}}"#,
        "\n"
    );
    let part = reqwest::multipart::Part::bytes(lines.as_bytes().to_vec())
        .file_name("in.jsonl")
        .mime_str("application/jsonl")
        .unwrap();
    let form = reqwest::multipart::Form::new()
        .text("purpose", "batch")
        .part("file", part);
    let r = client
        .post(format!("{base}/v1/files"))
        .header("Authorization", auth())
        .multipart(form)
        .send()
        .await
        .unwrap();
    let file_id = r.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    let r = client
        .post(format!("{base}/v1/batches"))
        .header("Authorization", auth())
        .json(&json!({"input_file_id": file_id, "endpoint": "/v1/chat/completions", "completion_window": "24h"}))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 200);
    let bid = r.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    // Seat loop until the batch completes: each line is its own
    // conversation.
    let mut answered: HashSet<String> = baseline;
    let mut out_file = String::new();
    for _ in 0..25 {
        for conv in waiting_convs(client, base).await {
            if answered.insert(conv.clone()) {
                seat_reply(client, base, &conv, json!({"text": "batch answer"})).await;
            }
        }
        let r = client
            .get(format!("{base}/v1/batches/{bid}"))
            .header("Authorization", auth())
            .send()
            .await
            .unwrap();
        let v: Value = r.json().await.unwrap();
        if v["status"] == "completed" {
            out_file = v["output_file_id"].as_str().unwrap_or("").to_string();
            break;
        }
        if v["status"] == "failed" || v["status"] == "expired" {
            panic!("batch ended as {}: {v}", v["status"]);
        }
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    }
    assert!(!out_file.is_empty(), "batch completed with an output file");
    let r = client
        .get(format!("{base}/v1/files/{out_file}/content"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    let body = r.text().await.unwrap();
    let rows: Vec<Value> = body
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    assert_eq!(rows.len(), 2, "one output row per input line: {body}");
    for row in rows {
        assert_eq!(row["response"]["status_code"], 200);
        let text = row
            .pointer("/response/body/choices/0/message/content")
            .and_then(|c| c.as_str())
            .unwrap_or("");
        assert_eq!(text, "batch answer", "row {}: {row}", row["custom_id"]);
    }
}

async fn e2e_assistants_run_roundtrip(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_assistants_run_roundtrip start");
    let r = client
        .post(format!("{base}/v1/assistants"))
        .header("Authorization", auth())
        .json(&json!({"model": "openhuman-human", "instructions": "answer briefly"}))
        .send()
        .await
        .unwrap();
    let asst = r.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    let r = client
        .post(format!("{base}/v1/threads"))
        .header("Authorization", auth())
        .json(&json!({"messages": [{"role": "user", "content": "what is 2+2?"}]}))
        .send()
        .await
        .unwrap();
    let tid = r.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let r = client
        .post(format!("{base}/v1/threads/{tid}/runs"))
        .header("Authorization", auth())
        .json(&json!({"assistant_id": asst}))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 200);
    let rid = r.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    let mut answered: HashSet<String> = baseline;
    let mut done = false;
    for _ in 0..25 {
        for conv in waiting_convs(client, base).await {
            if answered.insert(conv.clone()) {
                seat_reply(client, base, &conv, json!({"text": "4"})).await;
            }
        }
        let r = client
            .get(format!("{base}/v1/threads/{tid}/runs/{rid}"))
            .header("Authorization", auth())
            .send()
            .await
            .unwrap();
        let v: Value = r.json().await.unwrap();
        if v["status"] == "completed" {
            done = true;
            break;
        }
        if matches!(
            v["status"].as_str(),
            Some("failed" | "cancelled" | "expired")
        ) {
            panic!("run ended as {}: {v}", v["status"]);
        }
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    }
    assert!(done, "run completed");
    let r = client
        .get(format!("{base}/v1/threads/{tid}/messages"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    let v: Value = r.json().await.unwrap();
    let found = v["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|m| m["role"] == "assistant" && m.to_string().contains('4'));
    assert!(found, "assistant message in thread: {v}");
}

/// Agents API: owner isolation (a second principal sees nothing of
/// Alice's), type isolation (an agent id is not a session id), and the
/// task -> result round trip (session with input -> seat answer ->
/// completed turn, items carry the answer).
async fn e2e_agents_isolation_and_roundtrip(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_agents_isolation_and_roundtrip start");
    let r = client
        .post(format!("{base}/v1/agents"))
        .header("Authorization", auth())
        .json(&json!({"name": "Smoke Agent"}))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 200, "create agent");
    let aid = r.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    // Owner isolation: Bob cannot read, list or start a session on
    // Alice's agent.
    let r = client
        .get(format!("{base}/v1/agents/{aid}"))
        .header("Authorization", auth2())
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 404, "bob reads alice's agent");
    let r = client
        .get(format!("{base}/v1/agents"))
        .header("Authorization", auth2())
        .send()
        .await
        .unwrap();
    let v: Value = r.json().await.unwrap();
    assert!(
        v["data"].as_array().unwrap().is_empty(),
        "bob's agent list stays empty: {v}"
    );
    let r = client
        .post(format!("{base}/v1/agents/sessions"))
        .header("Authorization", auth2())
        .json(&json!({"agent_id": aid, "environment": {"type": "none"}}))
        .send()
        .await
        .unwrap();
    assert_eq!(
        r.status().as_u16(),
        404,
        "bob starts a session on alice's agent"
    );

    // Type isolation: an agent id is not a session.
    let r = client
        .get(format!("{base}/v1/agents/sessions/{aid}"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 404, "an agent id is not a session");

    // The task -> result round trip: a session with input runs a turn
    // that the seat answers.
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let r = client
        .post(format!("{base}/v1/agents/sessions"))
        .header("Authorization", auth())
        .json(&json!({"agent_id": aid, "environment": {"type": "none"}, "input": "what is 6*7?", "stream": false}))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 200, "create session");
    let sid = r.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    // More isolation, on the new session.
    let r = client
        .get(format!("{base}/v1/agents/{sid}"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 404, "a session id is not an agent");
    let r = client
        .get(format!("{base}/v1/agents/sessions/{sid}"))
        .header("Authorization", auth2())
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 404, "bob reads alice's session");

    let mut answered: HashSet<String> = baseline;
    let mut turn_done = false;
    for _ in 0..25 {
        for conv in waiting_convs(client, base).await {
            if answered.insert(conv.clone()) {
                seat_reply(client, base, &conv, json!({"text": "42"})).await;
            }
        }
        let r = client
            .get(format!("{base}/v1/agents/sessions/{sid}/turns"))
            .header("Authorization", auth())
            .send()
            .await
            .unwrap();
        let v: Value = r.json().await.unwrap();
        let turns = v["data"].as_array().unwrap();
        if turns.iter().any(|t| t["status"] == "failed") {
            panic!("the turn failed: {v}");
        }
        if turns.iter().any(|t| t["status"] == "completed") {
            turn_done = true;
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    }
    assert!(turn_done, "the session's turn completed");

    let r = client
        .get(format!("{base}/v1/agents/sessions/{sid}"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    let v: Value = r.json().await.unwrap();
    assert_eq!(v["status"], "idle", "session back to idle: {v}");

    let r = client
        .get(format!("{base}/v1/agents/sessions/{sid}/items"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    let v: Value = r.json().await.unwrap();
    let found = v["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|m| m["role"] == "assistant" && m.to_string().contains("42"));
    assert!(found, "assistant message in session items: {v}");
}

/// Videos: create -> queued -> the seat attaches an mp4 -> completed,
/// and /content returns the attachment's bytes.
async fn e2e_video_generation_roundtrip(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_video_generation_roundtrip start");
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let r = client
        .post(format!("{base}/v1/videos"))
        .header("Authorization", auth())
        .json(&json!({"prompt": "a dot moving left to right", "seconds": "4", "size": "720x1280"}))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 200, "create video");
    let v = r.json::<Value>().await.unwrap();
    let vid = v["id"].as_str().unwrap().to_string();

    let payload = format!("FAKEMP4-{}", uuid::Uuid::new_v4().simple()).into_bytes();
    let b64 = openhuman_server::openai_compat::b64_encode(&payload);
    let mut answered: HashSet<String> = baseline;
    let mut done = false;
    for _ in 0..25 {
        for conv in waiting_convs(client, base).await {
            if answered.insert(conv.clone()) {
                seat_reply(
                    client,
                    base,
                    &conv,
                    json!({"text": "", "attachments": [{"name": "clip.mp4", "mime": "video/mp4", "data": b64}]}),
                )
                .await;
            }
        }
        let r = client
            .get(format!("{base}/v1/videos/{vid}"))
            .header("Authorization", auth())
            .send()
            .await
            .unwrap();
        let v: Value = r.json().await.unwrap();
        match v["status"].as_str() {
            Some("completed") => {
                done = true;
                break;
            }
            Some("failed") => panic!("video failed: {v}"),
            _ => {}
        }
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    }
    assert!(done, "video completed");

    let r = client
        .get(format!("{base}/v1/videos/{vid}/content"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 200, "video content");
    let ct = r
        .headers()
        .get("content-type")
        .unwrap()
        .to_str()
        .unwrap()
        .to_string();
    assert!(ct.starts_with("video/mp4"), "content-type: {ct}");
    let bytes = r.bytes().await.unwrap();
    assert_eq!(
        &bytes[..],
        &payload[..],
        "the video bytes are the seat's attachment"
    );
}

/// ChatKit: threads.create streams SSE; the seat's answer arrives as
/// assistant_message deltas; the thread is then visible over REST.
async fn e2e_chatkit_thread_answer(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_chatkit_thread_answer start");
    let user = format!("e2e-{}", uuid::Uuid::new_v4().simple());
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let (b, c, u) = (base.to_string(), client.clone(), user.clone());
    // The SSE body ends only after the seat answered, so the spawned task
    // reads the whole body and `with_seat` waits on the full read.
    let req = tokio::spawn(async move {
        c.post(format!("{b}/v1/chatkit"))
            .header("Authorization", auth())
            .json(&json!({
                "type": "threads.create",
                "params": {"input": {"content": [{"type": "input_text", "text": "chatkit smoke question"}]}},
                "metadata": {"user": u},
            }))
            .send()
            .await
            .unwrap()
            .text()
            .await
            .unwrap()
    });
    let body = with_seat(
        client,
        base,
        baseline,
        req,
        json!({"text": "chatkit says hi"}),
    )
    .await;
    assert!(
        body.contains("\"thread.created\""),
        "thread.created in the stream: {body}"
    );
    assert!(
        body.contains("chatkit says hi"),
        "answer text in the stream: {body}"
    );
    let mut tid = String::new();
    for line in body.lines() {
        if let Some(data) = line.strip_prefix("data: ") {
            if let Ok(v) = serde_json::from_str::<Value>(data) {
                if v["type"] == "thread.created" {
                    tid = v["thread"]["id"].as_str().unwrap_or("").to_string();
                }
            }
        }
    }
    assert!(!tid.is_empty(), "thread id from the stream: {body}");

    let r = client
        .get(format!("{base}/v1/chatkit/threads?user={user}"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    let v: Value = r.json().await.unwrap();
    assert!(
        v["data"].as_array().unwrap().iter().any(|t| t["id"] == tid),
        "thread listed for its user: {v}"
    );
    let r = client
        .get(format!("{base}/v1/chatkit/threads/{tid}/items"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    let v: Value = r.json().await.unwrap();
    let found = v["data"].as_array().unwrap().iter().any(|i| {
        i["type"] == "chatkit.assistant_message" && i.to_string().contains("chatkit says hi")
    });
    assert!(found, "assistant item in the thread: {v}");
}

/// Evals: a run with one row; the string_check grader runs locally, the
/// label_model grader goes to the seat; the run completes passed.
async fn e2e_evals_run_with_seat_grader(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_evals_run_with_seat_grader start");
    let r = client
        .post(format!("{base}/v1/evals"))
        .header("Authorization", auth())
        .json(&json!({
            "name": "smoke-eval",
            "testing_criteria": [
                {"type": "string_check", "name": "exact", "input": "{{sample.output_text}}", "reference": "{{item.expected}}", "operation": "eq"},
                {"type": "label_model", "name": "judge", "model": "openhuman-human",
                 "input": [{"role": "user", "content": "Rate the sample: {{sample.output_text}}"}],
                 "labels": ["good", "bad"], "passing_labels": ["good"]},
            ],
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 200, "create eval");
    let eid = r.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let r = client
        .post(format!("{base}/v1/evals/{eid}/runs"))
        .header("Authorization", auth())
        .json(
            &json!({"data_source": {"source": {"type": "file_content", "content": [
                {"item": {"expected": "four"}, "sample": {"output_text": "four"}}
            ]}}}),
        )
        .send()
        .await
        .unwrap();
    assert_eq!(r.status().as_u16(), 200, "create run");
    let rid = r.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    let mut answered: HashSet<String> = baseline;
    let mut run = None;
    for _ in 0..25 {
        for conv in waiting_convs(client, base).await {
            if answered.insert(conv.clone()) {
                seat_reply(
                    client,
                    base,
                    &conv,
                    json!({"text": "{\"label\": \"good\"}"}),
                )
                .await;
            }
        }
        let r = client
            .get(format!("{base}/v1/evals/{eid}/runs/{rid}"))
            .header("Authorization", auth())
            .send()
            .await
            .unwrap();
        let v: Value = r.json().await.unwrap();
        match v["status"].as_str() {
            Some("completed") => {
                run = Some(v);
                break;
            }
            Some(s @ ("failed" | "canceled" | "cancelled")) => panic!("run ended as {s}: {v}"),
            _ => {}
        }
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    }
    let run = run.expect("run completed");
    assert_eq!(
        run["result_counts"],
        json!({"total": 1, "passed": 1, "failed": 0, "errored": 0}),
        "result counts: {run}"
    );

    let r = client
        .get(format!("{base}/v1/evals/{eid}/runs/{rid}/output_items"))
        .header("Authorization", auth())
        .send()
        .await
        .unwrap();
    let v: Value = r.json().await.unwrap();
    let items = v["data"].as_array().unwrap();
    assert_eq!(items.len(), 1, "one output item: {v}");
    assert_eq!(items[0]["status"], "pass", "output item: {v}");
}

/// Moderations: the seat's JSON verdict becomes the OpenAI result
/// shape, flagged per input.
async fn e2e_moderation_verdicts(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_moderation_verdicts start");
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let (b, c) = (base.to_string(), client.clone());
    let req = tokio::spawn(async move {
        c.post(format!("{b}/v1/moderations"))
            .header("Authorization", auth())
            .json(&json!({"input": ["a lovely day", "something else entirely"]}))
            .send()
            .await
            .unwrap()
    });
    let resp = with_seat(
        client,
        base,
        baseline,
        req,
        json!({"text": "[[\"violence\"], []]"}),
    )
    .await;
    assert_eq!(resp.status().as_u16(), 200);
    let v: Value = resp.json().await.unwrap();
    let results = v["results"].as_array().unwrap();
    assert_eq!(results.len(), 2, "one result per input: {v}");
    assert_eq!(results[0]["flagged"], true, "first input flagged: {v}");
    assert_eq!(results[0]["categories"]["violence"], true);
    assert_eq!(results[1]["flagged"], false, "second input clean: {v}");
    assert_eq!(results[1]["categories"]["violence"], false);
}

/// Decisions: a predicate and a choice question, answered by the seat
/// as a JSON list, become the OpenAI answers.
async fn e2e_decision_questions(client: &reqwest::Client, base: &str) {
    eprintln!("SCENARIO e2e_decision_questions start");
    let baseline: HashSet<String> = waiting_convs(client, base).await.into_iter().collect();
    let (b, c) = (base.to_string(), client.clone());
    let req = tokio::spawn(async move {
        c.post(format!("{b}/v1/decisions"))
            .header("Authorization", auth())
            .json(&json!({
                "questions": [
                    {"type": "predicate", "instructions": "is the input polite?"},
                    {"type": "choice", "instructions": "which language is it?", "choices": [{"value": "en"}, {"value": "fr"}]},
                ],
                "input": "hi, could you help me with this?",
            }))
            .send()
            .await
            .unwrap()
    });
    let resp = with_seat(
        client,
        base,
        baseline,
        req,
        json!({"text": "[0.9, \"FR\"]"}),
    )
    .await;
    assert_eq!(resp.status().as_u16(), 200);
    let v: Value = resp.json().await.unwrap();
    let answers = v["answers"].as_array().unwrap();
    assert_eq!(answers.len(), 2, "one answer per question: {v}");
    assert_eq!(answers[0]["type"], "predicate");
    assert_eq!(answers[0]["probability"], json!(0.9));
    assert_eq!(answers[1]["type"], "choice");
    assert_eq!(answers[1]["choice"], "fr");
    assert!(
        v["usage"]["total_tokens"].as_u64().unwrap_or(0) > 0,
        "usage: {v}"
    );
}

async fn run_all(client: &reqwest::Client, base: &str) {
    e2e_chat_answer_roundtrip(client, base).await;
    eprintln!("SCENARIO chat done");
    e2e_image_generation_with_attachment(client, base).await;
    eprintln!("SCENARIO images done");
    e2e_audio_transcription_text_answer(client, base).await;
    eprintln!("SCENARIO audio done");
    e2e_batch_two_lines_complete(client, base).await;
    eprintln!("SCENARIO batch done");
    e2e_assistants_run_roundtrip(client, base).await;
    eprintln!("SCENARIO assistants done");
    e2e_agents_isolation_and_roundtrip(client, base).await;
    eprintln!("SCENARIO agents done");
    e2e_video_generation_roundtrip(client, base).await;
    eprintln!("SCENARIO videos done");
    e2e_chatkit_thread_answer(client, base).await;
    eprintln!("SCENARIO chatkit done");
    e2e_evals_run_with_seat_grader(client, base).await;
    eprintln!("SCENARIO evals done");
    e2e_moderation_verdicts(client, base).await;
    eprintln!("SCENARIO moderations done");
    e2e_decision_questions(client, base).await;
    eprintln!("SCENARIO decisions done");
}

/// All eleven scenarios against one server, in sequence: the seat
/// globals bind to the first server a process builds, so one server
/// it is.
#[tokio::test]
async fn e2e_seat_smoke() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();
    run_all(&client, &base).await;
}

/// The same eleven scenarios against the Postgres backend. Ignored by
/// default: needs DATABASE_URL and must run alone (the seat globals bind
/// to one server per process, and this wipes the data tables):
///
///   DATABASE_URL=postgres://... cargo test --test e2e_seat_smoke -- --ignored
#[tokio::test]
#[ignore = "needs DATABASE_URL; run alone with --ignored"]
async fn e2e_seat_smoke_postgres() {
    let url = std::env::var("DATABASE_URL").expect("DATABASE_URL for the postgres smoke");
    std::env::set_var("OPENHUMAN_DEMO", "1");
    let store = openhuman_server::storage::postgres::PostgresStore::new(&url)
        .await
        .unwrap();
    store.migrate().await.unwrap();
    // migrate() revokes the demo key whenever it runs without
    // OPENHUMAN_DEMO=1; a shared dev database may carry that state, so
    // restore the demo key explicitly.
    sqlx::query("UPDATE api_keys SET scope = 'both' WHERE id = 'key_demo_001'")
        .execute(store.pool())
        .await
        .unwrap();
    // Start clean: leftovers from earlier runs would shadow the
    // assertions. Identities and keys stay (migrate re-seeded the demo).
    for t in [
        "messages",
        "conversation_participants",
        "conversations",
        "tasks",
        "files",
        "api_objects",
    ] {
        sqlx::query(&format!("DELETE FROM {t}"))
            .execute(store.pool())
            .await
            .unwrap();
    }
    // The second principal, matching `add_seeded_identity` on memory.
    for q in [
        "INSERT INTO identities (id, display_name, avatar_url, status, capabilities, metadata, created_at, updated_at) \
         VALUES ('hum_demo_bob', 'Bob Stone', NULL, 'online', '[]'::jsonb, '{}'::jsonb, NOW(), NOW()) \
         ON CONFLICT (id) DO NOTHING",
        "INSERT INTO agent_identities (id, name, client_type, api_key_id, capabilities, metadata, created_at, updated_at) \
         VALUES ('agt_demo_bob_executor', 'Bob Executor', 'codex', 'key_demo_002', '[]'::jsonb, '{}'::jsonb, NOW(), NOW()) \
         ON CONFLICT (id) DO NOTHING",
        "INSERT INTO api_keys (id, key_hash, agent_id, human_id, created_at) \
         VALUES ('key_demo_002', encode(digest('ohk_demo_bob_executor', 'sha256'), 'hex'), 'agt_demo_bob_executor', 'hum_demo_bob', NOW()) \
         ON CONFLICT (id) DO NOTHING",
    ] {
        sqlx::query(q).execute(store.pool()).await.unwrap();
    }
    let state = AppState::from_postgres(
        store,
        openhuman_server::storage::postgres::InMemoryReplyRegistry::new(),
    );
    // Tasks a previous process left queued will never be answered; fail
    // them honestly, like the server boot does.
    state
        .task
        .fail_in_flight_tasks("test server restarted")
        .await;
    let base = spawn_app(build_router(state)).await;
    let client = reqwest::Client::new();
    run_all(&client, &base).await;
}
