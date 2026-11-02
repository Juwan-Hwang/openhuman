//! Tests for the behaviors ported from omni2api's post-split work:
//! `/v1/files`, the seat-chosen model name, and resubmitted-turn supersede.

use openhuman_server::build_router;
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::{AppState, ModelName, SeatNameError};

const DEMO_KEY: &str = "ohk_demo_alice_codex";

fn test_app() -> axum::Router {
    std::env::set_var("OPENHUMAN_MOCK_ENDPOINTS", "1");
    let store = MemoryStore::seeded();
    let state = AppState::from_store(store);
    build_router(state)
}

async fn spawn_server() -> String {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{}", addr)
}

// ── /v1/files ──

#[tokio::test]
async fn files_upload_list_content_delete_roundtrip() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();

    let part = reqwest::multipart::Part::bytes(b"hello openhuman".to_vec())
        .file_name("greeting.txt")
        .mime_str("text/plain")
        .unwrap();
    let form = reqwest::multipart::Form::new()
        .text("purpose", "assistants")
        .part("file", part);
    let resp = client
        .post(format!("{}/v1/files", base))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .multipart(form)
        .send()
        .await
        .unwrap();
    let status = resp.status();
    let text = resp.text().await.unwrap();
    assert_eq!(status, 200, "upload: {}", text);
    let body: serde_json::Value = serde_json::from_str(&text).unwrap();
    let file_id = body["id"].as_str().unwrap().to_string();
    assert!(file_id.starts_with("file-"));
    assert_eq!(body["filename"], "greeting.txt");

    // Metadata
    let resp = client
        .get(format!("{}/v1/files/{}", base, file_id))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);

    // Content roundtrip
    let resp = client
        .get(format!("{}/v1/files/{}/content", base, file_id))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);
    assert_eq!(resp.text().await.unwrap(), "hello openhuman");

    // Delete
    let resp = client
        .delete(format!("{}/v1/files/{}", base, file_id))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);
    let resp = client
        .get(format!("{}/v1/files/{}/content", base, file_id))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 404);
}

#[tokio::test]
async fn files_require_auth() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();
    let resp = client
        .get(format!("{}/v1/files", base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 401);
}

// ── seat-chosen model name ──

#[tokio::test]
async fn seat_can_name_the_model() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();

    let resp = client
        .post(format!("{}/v1/seat/model-name", base))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .json(&serde_json::json!({"name": "alice-panel"}))
        .send()
        .await
        .unwrap();
    let status = resp.status();
    let text = resp.text().await.unwrap();
    assert_eq!(status, 200, "set: {}", text);

    let resp = client
        .get(format!("{}/v1/models", base))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .send()
        .await
        .unwrap();
    let body: serde_json::Value = resp.json().await.unwrap();
    assert_eq!(body["data"][0]["id"], "alice-panel");

    // Invalid names are refused.
    let resp = client
        .post(format!("{}/v1/seat/model-name", base))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .json(&serde_json::json!({"name": "has whitespace"}))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 400);

    // Reset so other tests in this process see the default again.
    let resp = client
        .post(format!("{}/v1/seat/model-name", base))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .json(&serde_json::json!({"name": "openhuman-human"}))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);
}

#[test]
fn user_pinned_name_locks_out_the_seat() {
    let m = ModelName::from_env();
    m.set_user("pinned");
    assert!(matches!(m.set_seat("other"), Err(SeatNameError::Locked)));
    assert_eq!(m.get(), "pinned");
    assert!(m.is_locked());
}

#[test]
fn default_model_name_is_openhuman_human() {
    // Backward compatibility: existing callers are configured with
    // `model: openhuman-human`; the default must not change under them.
    let m = ModelName::from_env();
    assert_eq!(m.get(), "openhuman-human");
}

// ── resubmitted turn supersedes ──

#[tokio::test]
async fn resubmitted_turn_supersedes_over_http() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();
    let conversation = "port-supersede-test";

    // Request 1 opens a streaming turn and waits.
    let first = {
        let client = client.clone();
        let base = base.clone();
        tokio::spawn(async move {
            client
                .post(format!("{}/v1/chat/completions", base))
                .header("Authorization", format!("Bearer {}", DEMO_KEY))
                .header("X-OpenHuman-Conversation-Id", conversation)
                .json(&serde_json::json!({
                    "model": "openhuman-human",
                    "messages": [{"role": "user", "content": "first attempt"}],
                    "stream": true
                }))
                .send()
                .await
                .unwrap()
        })
    };
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;

    // Request 2 on the same conversation must not get 409: it takes over.
    let second = client
        .post(format!("{}/v1/chat/completions", base))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .header("X-OpenHuman-Conversation-Id", conversation)
        .json(&serde_json::json!({
            "model": "openhuman-human",
            "messages": [{"role": "user", "content": "retry"}],
            "stream": true
        }))
        .send()
        .await
        .unwrap();
    let status = second.status();
    if status != 200 {
        panic!("resubmit refused with {}: {}", status, second.text().await.unwrap());
    }

    // Let the second request register its waiter before the reply lands.
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;

    // The human's reply goes to the connection still listening.
    let resp = client
        .post(format!("{}/v1/mock/human-reply", base))
        .json(&serde_json::json!({
            "agent_id": "agt_demo_codex",
            "text": "the answer"
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);

    // A text reply alone leaves a multi-turn stream open; end the turn.
    let resp = client
        .post(format!("{}/v1/mock/end-turn", base))
        .json(&serde_json::json!({"agent_id": "agt_demo_codex"}))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200, "end-turn: {}", resp.text().await.unwrap_or_default());

    let body = second.text().await.unwrap();
    // The reply streams as word-sized chunks ("the " + "answer"), so match
    // the piece that cannot be split further.
    assert!(body.contains("answer"), "second gets the reply: {}", body);

    // The superseded first request ends instead of hanging.
    let first = tokio::time::timeout(std::time::Duration::from_secs(10), first)
        .await
        .expect("superseded request must end, not hang")
        .unwrap();
    let first_body = first.text().await.unwrap();
    assert!(
        !first_body.contains("answer"),
        "superseded request must not receive the reply"
    );
}
