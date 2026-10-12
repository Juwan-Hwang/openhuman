//! Integration tests for asynchronous reply mode and conversation scoping.
//!
//! Covers the two behaviours that are easy to break silently:
//!
//! 1. A turn submitted with `X-OpenHuman-Mode: async` must return `202` with
//!    an `invocation_id`, and the human's eventual reply must be retrievable
//!    from `GET /v1/replies/{id}` — including when the reply is a tool call.
//! 2. Requests carrying different conversation ids must land in different
//!    conversations rather than one shared transcript.

use openhuman_server::build_router;
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::AppState;

const DEMO_KEY: &str = "ohk_demo_alice_codex";

fn test_app() -> axum::Router {
    // The /v1/mock/* harness is disabled unless explicitly enabled;
    // these tests drive turns through it, so opt in for the test run.
    std::env::set_var("OPENHUMAN_MOCK_ENDPOINTS", "1");
    let store = MemoryStore::seeded();
    let state = AppState::from_store(store);
    build_router(state)
}

/// Start a server on an ephemeral port and return its base URL.
async fn spawn_server() -> String {
    let app = test_app();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{}", addr)
}

// ── 1. Async round trip ──

#[tokio::test]
async fn async_turn_returns_202_then_completes_after_human_reply() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();

    let resp = client
        .post(format!("{}/v1/chat/completions", base))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .header("X-OpenHuman-Mode", "async")
        .json(&serde_json::json!({
            "model": "openhuman-human",
            "messages": [{"role": "user", "content": "Async question"}]
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(resp.status(), 202, "async mode must not block on the human");

    let accepted: serde_json::Value = resp.json().await.unwrap();
    let invocation_id = accepted["id"]
        .as_str()
        .expect("202 body carries an id")
        .to_string();
    assert!(invocation_id.starts_with("inv_"), "got {invocation_id}");
    assert_eq!(accepted["status"], "pending");
    let poll_url = accepted["poll_url"].as_str().unwrap().to_string();
    assert!(poll_url.contains(&invocation_id));

    // Not answered yet. `?wait=1` keeps the test fast — the default
    // long-poll would otherwise sit out its full 30s budget.
    let pending = client
        .get(format!("{}{}?wait=1", base, poll_url))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .send()
        .await
        .unwrap();
    assert_eq!(pending.status(), 200);
    let pending: serde_json::Value = pending.json().await.unwrap();
    assert_eq!(pending["status"], "pending");

    // The human answers.
    let mock = client
        .post(format!("{}/v1/mock/human-reply", base))
        .json(&serde_json::json!({
            "agent_id": "agt_demo_codex",
            "text": "Here is your answer"
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(
        mock.status(),
        200,
        "mock reply should complete the invocation"
    );

    // Now the poll returns a normal-looking completion.
    let done = client
        .get(format!("{}{}", base, poll_url))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .send()
        .await
        .unwrap();
    assert_eq!(done.status(), 200);
    let done: serde_json::Value = done.json().await.unwrap();
    assert_eq!(done["status"], "completed");

    let message = &done["choices"][0]["message"];
    assert_eq!(message["role"], "assistant");
    assert_eq!(message["content"], "Here is your answer");
    assert_eq!(done["choices"][0]["finish_reason"], "stop");
}

#[tokio::test]
async fn async_tool_call_is_not_downgraded_to_text() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();

    let resp = client
        .post(format!("{}/v1/chat/completions", base))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .header("X-OpenHuman-Mode", "async")
        .json(&serde_json::json!({
            "model": "openhuman-human",
            "messages": [{"role": "user", "content": "Run a command"}]
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 202);
    let accepted: serde_json::Value = resp.json().await.unwrap();
    let poll_url = accepted["poll_url"].as_str().unwrap().to_string();

    let mock = client
        .post(format!("{}/v1/mock/tool-call", base))
        .json(&serde_json::json!({
            "agent_id": "agt_demo_codex",
            "tool_name": "Bash",
            "arguments": {"command": "echo hello"}
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(mock.status(), 200);

    let done: serde_json::Value = client
        .get(format!("{}{}", base, poll_url))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();

    assert_eq!(done["status"], "completed");
    let message = &done["choices"][0]["message"];
    // The regression this guards: a tool call must arrive as a tool_calls
    // array with finish_reason "tool_calls", never as a JSON string with
    // finish_reason "stop" — clients only act on the array.
    assert!(
        message.get("tool_calls").is_some(),
        "tool call must surface as tool_calls, got {message}"
    );
    assert_eq!(message["tool_calls"][0]["function"]["name"], "Bash");
    assert_eq!(message["tool_calls"][0]["type"], "function");
    assert_eq!(done["choices"][0]["finish_reason"], "tool_calls");

    let args: serde_json::Value = serde_json::from_str(
        message["tool_calls"][0]["function"]["arguments"]
            .as_str()
            .unwrap(),
    )
    .unwrap();
    assert_eq!(args, serde_json::json!({"command": "echo hello"}));
}

#[tokio::test]
async fn unknown_invocation_is_404() {
    let base = spawn_server().await;
    let resp = reqwest::Client::new()
        .get(format!("{}/v1/replies/inv_doesnotexist", base))
        .header("Authorization", format!("Bearer {}", DEMO_KEY))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 404);
}

#[tokio::test]
async fn replies_endpoint_requires_auth() {
    let base = spawn_server().await;
    let resp = reqwest::Client::new()
        .get(format!("{}/v1/replies/inv_anything", base))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 401);
}

// ── 2. Conversation scoping ──

/// Two chat windows that share one API key must not share one transcript.
#[tokio::test]
async fn distinct_conversation_ids_create_distinct_conversations() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();

    async fn ask(client: &reqwest::Client, base: &str, conversation: &str) -> String {
        let resp = client
            .post(format!("{}/v1/chat/completions", base))
            .header("Authorization", format!("Bearer {}", DEMO_KEY))
            .header("X-OpenHuman-Conversation-Id", conversation)
            .header("X-OpenHuman-Mode", "async")
            .json(&serde_json::json!({
                "model": "openhuman-human",
                "messages": [{"role": "user", "content": "hello"}]
            }))
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status(), 202);
        let body: serde_json::Value = resp.json().await.unwrap();
        body["conversation_id"].as_str().unwrap().to_string()
    }

    let a = ask(&client, &base, "window-a").await;
    let b = ask(&client, &base, "window-b").await;
    let a_again = ask(&client, &base, "window-a").await;

    assert_ne!(a, b, "separate chat windows must not share a conversation");
    assert_eq!(
        a, a_again,
        "the same window must resume its own conversation"
    );
}

/// Without a conversation id, requests fall back to a single shared scope —
/// documented behaviour, and the reason callers are told to pass one.
#[tokio::test]
async fn no_conversation_id_shares_the_default_scope() {
    let base = spawn_server().await;
    let client = reqwest::Client::new();

    async fn ask(client: &reqwest::Client, base: &str) -> String {
        let resp = client
            .post(format!("{}/v1/chat/completions", base))
            .header("Authorization", format!("Bearer {}", DEMO_KEY))
            .header("X-OpenHuman-Mode", "async")
            .json(&serde_json::json!({
                "model": "openhuman-human",
                "messages": [{"role": "user", "content": "hello"}]
            }))
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status(), 202);
        let body: serde_json::Value = resp.json().await.unwrap();
        body["conversation_id"].as_str().unwrap().to_string()
    }

    let first = ask(&client, &base).await;
    let second = ask(&client, &base).await;
    assert_eq!(first, second);
}
