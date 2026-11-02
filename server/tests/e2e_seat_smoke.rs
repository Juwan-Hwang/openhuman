//! End-to-end smoke: a scripted seat answers through the real seat API
//! (`GET /v1/seat/inbox`, `POST /v1/seat/reply`) while a client drives
//! the OpenAI-shaped endpoints. Covers chat, images, audio
//! (transcription), batches and assistants: task card -> seat reply ->
//! client gets the result.

use std::collections::HashSet;

use openhuman_server::build_router;
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::AppState;
use serde_json::{json, Value};

const KEY: &str = "ohk_demo_alice_codex";

async fn spawn_server() -> String {
    let app = build_router(AppState::from_store(MemoryStore::seeded()));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
}

fn auth() -> String {
    format!("Bearer {KEY}")
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
async fn with_seat(
    client: &reqwest::Client,
    base: &str,
    baseline: HashSet<String>,
    request: tokio::task::JoinHandle<reqwest::Response>,
    answer: Value,
) -> reqwest::Response {
    let request = request;
    // Conversations waiting before this scenario are leftovers from the
    // previous one; never answer them twice (a chat conversation rejects
    // attachments, an answered task is gone anyway).
    let mut answered: HashSet<String> = baseline;
    let resp = loop {
        if request.is_finished() {
            break request.await.unwrap();
        }
        for conv in waiting_convs(client, base).await {
            if answered.insert(conv.clone()) {
                seat_reply(client, base, &conv, answer.clone()).await;
            }
        }
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
    };
    resp
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

/// All five scenarios against one server, in sequence: the seat globals
/// bind to the first server a process builds, so one server it is.
#[tokio::test]
async fn e2e_seat_smoke() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();
    e2e_chat_answer_roundtrip(&client, &base).await;
    eprintln!("SCENARIO chat done");
    e2e_image_generation_with_attachment(&client, &base).await;
    eprintln!("SCENARIO images done");
    e2e_audio_transcription_text_answer(&client, &base).await;
    eprintln!("SCENARIO audio done");
    e2e_batch_two_lines_complete(&client, &base).await;
    eprintln!("SCENARIO batch done");
    e2e_assistants_run_roundtrip(&client, &base).await;
    eprintln!("SCENARIO assistants done");
}
