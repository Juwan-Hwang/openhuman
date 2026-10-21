//! Integration tests for the OpenAI-compatible API.
//!
//! Tests run against the in-memory store via `AppState`.
//! The same tests will pass unchanged when the store backend
//! switches to PostgreSQL.

use openhuman_server::build_router;
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::AppState;

/// Demo API key seeded in the store.
const DEMO_KEY: &str = "ohk_demo_alice_codex";

fn test_app() -> axum::Router {
    // The /v1/mock/* harness is disabled unless explicitly enabled;
    // these tests drive turns through it, so opt in for the test run.
    std::env::set_var("OPENHUMAN_MOCK_ENDPOINTS", "1");
    let store = MemoryStore::seeded();
    let state = AppState::from_store(store);
    build_router(state)
}

// ── 1. Authentication ──

#[tokio::test]
async fn test_missing_auth_header_returns_401() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/chat/completions", addr))
        .json(&serde_json::json!({
            "model": "human",
            "messages": [{"role": "user", "content": "hi"}]
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(resp.status(), 401);
    let body: serde_json::Value = resp.json().await.unwrap();
    assert_eq!(body["error"]["code"], "missing_api_key");
}

#[tokio::test]
async fn test_invalid_api_key_returns_401() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let resp = reqwest::Client::new()
        .post(format!("http://{}/v1/chat/completions", addr))
        .header("Authorization", "Bearer ohk_invalid_key")
        .json(&serde_json::json!({
            "model": "human",
            "messages": [{"role": "user", "content": "hi"}]
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(resp.status(), 401);
    let body: serde_json::Value = resp.json().await.unwrap();
    assert_eq!(body["error"]["code"], "invalid_api_key");
}

// ── 2. Non-streaming chat completion ──

#[tokio::test]
async fn test_non_streaming_completion() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let client = reqwest::Client::new();

    let send_task = tokio::spawn({
        let client = client.clone();
        async move {
            client
                .post(format!("http://{}/v1/chat/completions", addr))
                .header("Authorization", format!("Bearer {}", DEMO_KEY))
                .json(&serde_json::json!({
                    "model": "human",
                    "messages": [
                        {"role": "system", "content": "You are a code reviewer."},
                        {"role": "user", "content": "Review src/auth.rs"}
                    ],
                    "stream": false
                }))
                .send()
                .await
                .unwrap()
        }
    });

    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    let _ = client
        .post(format!("http://{}/v1/mock/human-reply", addr))
        .json(&serde_json::json!({
            "agent_id": "agt_demo_codex",
            "text": "The auth code looks solid. Ship it."
        }))
        .send()
        .await
        .unwrap();

    let resp = send_task.await.unwrap();
    assert_eq!(resp.status(), 200);

    let body: serde_json::Value = resp.json().await.unwrap();
    assert_eq!(body["object"], "chat.completion");
    assert_eq!(body["model"], "openhuman-human");
    assert_eq!(body["choices"][0]["message"]["role"], "assistant");
    assert_eq!(
        body["choices"][0]["message"]["content"],
        "The auth code looks solid. Ship it."
    );
    assert_eq!(body["choices"][0]["finish_reason"], "stop");
    // Usage is computed server-side with a real tokenizer (never estimated).
    let prompt = body["usage"]["prompt_tokens"].as_u64().unwrap();
    let completion = body["usage"]["completion_tokens"].as_u64().unwrap();
    assert!(prompt > 0 && completion > 0);
    assert_eq!(
        body["usage"]["total_tokens"].as_u64().unwrap(),
        prompt + completion
    );
}

// ── 3. Streaming chat completion (SSE) ──

#[tokio::test]
async fn test_streaming_completion_sse() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let client = reqwest::Client::new();

    let send_task = tokio::spawn({
        let client = client.clone();
        async move {
            client
                .post(format!("http://{}/v1/chat/completions", addr))
                .header("Authorization", format!("Bearer {}", DEMO_KEY))
                .json(&serde_json::json!({
                    "model": "human",
                    "messages": [
                        {"role": "user", "content": "Say hello"}
                    ],
                    "stream": true
                }))
                .send()
                .await
                .unwrap()
        }
    });

    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    let reply_resp = client
        .post(format!("http://{}/v1/mock/human-reply", addr))
        .json(&serde_json::json!({
            "agent_id": "agt_demo_codex",
            "text": "Hello world"
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(
        reply_resp.status(),
        200,
        "human-reply should reach the waiting SSE handler"
    );

    // Multi-turn streaming stays open after a text reply — the human may
    // have more to say — so the turn has to be closed explicitly. Without
    // this the SSE stream never emits its finish chunk and the test hangs.
    let end_resp = client
        .post(format!("http://{}/v1/mock/end-turn", addr))
        .json(&serde_json::json!({ "agent_id": "agt_demo_codex" }))
        .send()
        .await
        .unwrap();
    assert_eq!(
        end_resp.status(),
        200,
        "end-turn should reach the waiting SSE handler"
    );

    let resp = send_task.await.unwrap();
    assert_eq!(resp.status(), 200);
    assert_eq!(
        resp.headers()
            .get("content-type")
            .unwrap()
            .to_str()
            .unwrap(),
        "text/event-stream"
    );

    let body = resp.text().await.unwrap();

    assert!(
        body.contains("\"delta\":{\"role\":\"assistant\"}"),
        "Missing role header chunk"
    );
    assert!(body.contains("Hello"), "Missing content 'Hello'");
    assert!(body.contains("world"), "Missing content 'world'");
    assert!(
        body.contains("\"finish_reason\":\"stop\""),
        "Missing finish chunk"
    );
    assert!(body.contains("[DONE]"), "Missing [DONE] marker");
}

// ── 4. Health check ──

#[tokio::test]
async fn test_health_check() {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let resp = reqwest::get(format!("http://{}/health", addr))
        .await
        .unwrap();

    assert_eq!(resp.status(), 200);
    assert_eq!(resp.text().await.unwrap(), "ok");
}
