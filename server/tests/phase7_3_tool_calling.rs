//! Phase 7.3 — OpenAI Tool Calling Validation Tests
//!
//! Tests that:
//! 1. `tool_calls` response serialization matches OpenAI spec
//! 2. `role=tool` messages parse correctly with `tool_call_id`
//! 3. `tool_call_id` correlation works across messages
//! 4. Non-streaming tool_call response is correct
//! 5. SSE streaming tool_call chunks are correct
//! 6. `POST /v1/mock/tool-call` endpoint delivers tool_call payload
//! 7. `parse_reply` correctly distinguishes text vs tool_call

use openhuman_server::openai_compat::{
    ChatCompletionChunk, ChatCompletionResponse, ChatContent, ChatMessage, ChatRole,
};

use serde_json::json;

// ── 1. Tool Calls Response Serialization ──

#[test]
fn test_tool_calls_response_serialization() {
    let args = json!({"command": "echo hello"});
    let resp = ChatCompletionResponse::from_tool_call("Bash", &args);
    let j = serde_json::to_value(&resp).unwrap();

    // Top-level fields
    assert_eq!(j["object"], "chat.completion");
    assert_eq!(j["model"], "openhuman-human");
    assert!(j["id"].as_str().unwrap().starts_with("chatcmpl-"));

    // Choices
    assert_eq!(j["choices"][0]["finish_reason"], "tool_calls");
    assert_eq!(j["choices"][0]["index"], 0);

    // Message
    let msg = &j["choices"][0]["message"];
    assert_eq!(msg["role"], "assistant");
    assert!(msg["content"].is_null());

    // tool_calls
    let tc = &msg["tool_calls"][0];
    assert!(tc["id"].as_str().unwrap().starts_with("call_"));
    assert_eq!(tc["type"], "function");
    assert_eq!(tc["function"]["name"], "Bash");
    assert_eq!(tc["function"]["arguments"], r#"{"command":"echo hello"}"#);
}

#[test]
fn test_text_reply_no_tool_calls_field() {
    let resp = ChatCompletionResponse::from_human_reply("Hello!");
    let j = serde_json::to_value(&resp).unwrap();
    // tool_calls should be absent (skip_serializing_if = "Option::is_none")
    assert!(j["choices"][0]["message"].get("tool_calls").is_none());
    assert_eq!(j["choices"][0]["finish_reason"], "stop");
}

// ── 2. Role=tool Message Parsing ──

#[test]
fn test_role_tool_message_full_round_trip() {
    // 1. Agent sends user message
    // 2. OpenHuman returns tool_calls (assistant message)
    // 3. Agent executes tool, sends role=tool message back

    // Step 2: tool_calls response
    let args = json!({"file_path": "/tmp/test.txt"});
    let resp = ChatCompletionResponse::from_tool_call("Read", &args);
    let resp_json = serde_json::to_value(&resp).unwrap();
    let call_id = resp_json["choices"][0]["message"]["tool_calls"][0]["id"]
        .as_str()
        .unwrap()
        .to_string();

    // Step 3: agent sends role=tool message
    let tool_msg_json = json!({
        "role": "tool",
        "content": "File contents: Hello World",
        "tool_call_id": call_id
    });
    let tool_msg: ChatMessage = serde_json::from_value(tool_msg_json).unwrap();

    assert_eq!(tool_msg.role, ChatRole::Tool);
    assert_eq!(tool_msg.tool_call_id, Some(call_id));
    assert_eq!(tool_msg.content.to_text(), "File contents: Hello World");
}

#[test]
fn test_role_tool_without_tool_call_id() {
    // Some agents might omit tool_call_id — should still parse
    let json = json!({
        "role": "tool",
        "content": "result without id"
    });
    let msg: ChatMessage = serde_json::from_value(json).unwrap();
    assert_eq!(msg.role, ChatRole::Tool);
    assert!(msg.tool_call_id.is_none());
    assert_eq!(msg.content.to_text(), "result without id");
}

// ── 3. Tool Call ID Correlation ──

#[test]
fn test_tool_call_id_correlation() {
    // Simulate a full conversation: user → tool_calls → tool result → user

    let messages = json!([
        {"role": "user", "content": "What files are in this directory?"},
        {"role": "assistant", "content": null, "tool_calls": [{
            "id": "call_001",
            "type": "function",
            "function": {"name": "Bash", "arguments": "{\"command\": \"ls\"}"}
        }]},
        {"role": "tool", "content": "file1.txt\nfile2.txt", "tool_call_id": "call_001"},
        {"role": "user", "content": "Great, now read file1.txt"}
    ]);

    let parsed: Vec<ChatMessage> = serde_json::from_value(messages).unwrap();
    assert_eq!(parsed.len(), 4);

    // Message 0: user
    assert_eq!(parsed[0].role, ChatRole::User);
    assert!(parsed[0].content.to_text().contains("What files"));

    // Message 1: assistant with tool_calls
    assert_eq!(parsed[1].role, ChatRole::Assistant);
    assert!(matches!(parsed[1].content, ChatContent::Null));
    let tc = parsed[1].tool_calls.as_ref().unwrap();
    assert_eq!(tc[0]["id"], "call_001");
    assert_eq!(tc[0]["function"]["name"], "Bash");

    // Message 2: tool result — tool_call_id correlates
    assert_eq!(parsed[2].role, ChatRole::Tool);
    assert_eq!(parsed[2].tool_call_id, Some("call_001".to_string()));
    assert_eq!(parsed[2].content.to_text(), "file1.txt\nfile2.txt");

    // Message 3: user follow-up
    assert_eq!(parsed[3].role, ChatRole::User);
    assert!(parsed[3].content.to_text().contains("read file1.txt"));
}

// ── 4. SSE Streaming Tool Call Chunks ──

#[test]
fn test_tool_call_delta_chunk_serialization() {
    let chunk = ChatCompletionChunk::tool_call_delta(
        "chatcmpl-test",
        "call_abc",
        "Bash",
        r#"{"command":"ls"}"#,
    );
    let j = serde_json::to_value(&chunk).unwrap();

    assert_eq!(j["object"], "chat.completion.chunk");
    assert_eq!(j["id"], "chatcmpl-test");

    let delta = &j["choices"][0]["delta"];
    // In tool_call delta, role and content should be absent
    assert!(delta.get("role").is_none() || delta["role"].is_null());
    assert!(delta.get("content").is_none() || delta["content"].is_null());

    // tool_calls should be present
    let tc = &delta["tool_calls"][0];
    assert_eq!(tc["index"], 0);
    assert_eq!(tc["id"], "call_abc");
    assert_eq!(tc["type"], "function");
    assert_eq!(tc["function"]["name"], "Bash");
    assert_eq!(tc["function"]["arguments"], r#"{"command":"ls"}"#);
}

#[test]
fn test_finish_tool_calls_chunk() {
    let chunk = ChatCompletionChunk::finish_tool_calls("chatcmpl-test");
    let j = serde_json::to_value(&chunk).unwrap();

    assert_eq!(j["choices"][0]["finish_reason"], "tool_calls");
    let delta = &j["choices"][0]["delta"];
    assert!(delta.get("content").is_none() || delta["content"].is_null());
    assert!(delta.get("tool_calls").is_none() || delta["tool_calls"].is_null());
}

#[test]
fn test_normal_finish_chunk_still_works() {
    let chunk = ChatCompletionChunk::finish("chatcmpl-test");
    let j = serde_json::to_value(&chunk).unwrap();
    assert_eq!(j["choices"][0]["finish_reason"], "stop");
}

// ── 5. Multiple Tool Calls in One Response ──

#[test]
fn test_multiple_tool_calls_in_assistant_message() {
    // Some agents send multiple tool_calls in one assistant message
    let json = json!({
        "role": "assistant",
        "content": null,
        "tool_calls": [
            {"id": "call_1", "type": "function", "function": {"name": "Read", "arguments": "{\"file_path\":\"a.txt\"}"}},
            {"id": "call_2", "type": "function", "function": {"name": "Read", "arguments": "{\"file_path\":\"b.txt\"}"}}
        ]
    });
    let msg: ChatMessage = serde_json::from_value(json).unwrap();
    assert_eq!(msg.role, ChatRole::Assistant);
    let tc = msg.tool_calls.as_ref().unwrap();
    assert_eq!(tc.as_array().unwrap().len(), 2);
    assert_eq!(tc[0]["id"], "call_1");
    assert_eq!(tc[1]["id"], "call_2");
}

// ── 6. Integration: mock/tool-call endpoint ──

mod integration {
    use openhuman_server::build_router;
    use openhuman_server::storage::memory::MemoryStore;
    use openhuman_server::storage::AppState;
    use serde_json::json;

    const DEMO_KEY: &str = "ohk_demo_alice_codex";

    fn test_app() -> axum::Router {
        // The /v1/mock/* harness is disabled unless explicitly enabled;
        // these tests drive turns through it, so opt in for the test run.
        std::env::set_var("OPENHUMAN_MOCK_ENDPOINTS", "1");
        let store = MemoryStore::seeded();
        let state = AppState::from_store(store);
        build_router(state)
    }

    /// End-to-end test: Agent POST → mock tool-call → Agent gets tool_calls response.
    #[tokio::test]
    async fn test_tool_call_via_mock_endpoint_non_streaming() {
        let app = test_app();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        let client = reqwest::Client::new();

        // 1. Agent sends a non-streaming request
        let agent_task = {
            let client = client.clone();
            let url = format!("http://{}/v1/chat/completions", addr);
            tokio::spawn(async move {
                client
                    .post(&url)
                    .header("Authorization", format!("Bearer {}", DEMO_KEY))
                    .json(&json!({
                        "model": "openhuman-human",
                        "messages": [{"role": "user", "content": "list files"}],
                        "stream": false,
                        "tools": [{
                            "type": "function",
                            "function": {
                                "name": "Bash",
                                "description": "execute shell commands",
                                "parameters": {"type": "object"}
                            }
                        }]
                    }))
                    .send()
                    .await
                    .unwrap()
            })
        };

        // 2. Wait for the conversation to be created
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;

        // 3. Trigger tool call via mock endpoint
        let resp = client
            .post(format!("http://{}/v1/mock/tool-call", addr))
            .json(&json!({
                "agent_id": "agt_demo_codex",
                "tool_name": "Bash",
                "arguments": {"command": "echo hello"}
            }))
            .send()
            .await
            .unwrap();

        assert_eq!(resp.status(), 200);
        let body: serde_json::Value = resp.json().await.unwrap();
        assert_eq!(body["ok"], true);
        assert_eq!(body["tool_name"], "Bash");
        assert_eq!(body["delivered"], true);

        // 4. Agent should receive a tool_calls response
        let resp = agent_task.await.unwrap();
        assert_eq!(resp.status(), 200);
        let body: serde_json::Value = resp.json().await.unwrap();

        assert_eq!(body["choices"][0]["finish_reason"], "tool_calls");
        assert!(body["choices"][0]["message"]["content"].is_null());
        assert_eq!(
            body["choices"][0]["message"]["tool_calls"][0]["function"]["name"],
            "Bash"
        );
        assert_eq!(
            body["choices"][0]["message"]["tool_calls"][0]["function"]["arguments"],
            r#"{"command":"echo hello"}"#
        );
    }

    /// End-to-end test: streaming SSE with tool_call delta chunks.
    #[tokio::test]
    async fn test_tool_call_via_mock_endpoint_streaming() {
        let app = test_app();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        let client = reqwest::Client::new();

        // 1. Agent sends a streaming request
        let agent_task = {
            let client = client.clone();
            let url = format!("http://{}/v1/chat/completions", addr);
            tokio::spawn(async move {
                client
                    .post(&url)
                    .header("Authorization", format!("Bearer {}", DEMO_KEY))
                    .json(&json!({
                        "model": "openhuman-human",
                        "messages": [{"role": "user", "content": "list files"}],
                        "stream": true,
                        "tools": [{
                            "type": "function",
                            "function": {"name": "Bash", "parameters": {}}
                        }]
                    }))
                    .send()
                    .await
                    .unwrap()
            })
        };

        // 2. Wait for SSE to register
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;

        // 3. Trigger tool call
        let resp = client
            .post(format!("http://{}/v1/mock/tool-call", addr))
            .json(&json!({
                "agent_id": "agt_demo_codex",
                "tool_name": "Bash",
                "arguments": {"command": "echo hello"}
            }))
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status(), 200);

        // 4. Read SSE stream — should contain tool_calls delta
        let resp = agent_task.await.unwrap();
        assert_eq!(resp.status(), 200);
        let body = resp.text().await.unwrap();

        // SSE should contain tool_calls and [DONE]
        assert!(
            body.contains("tool_calls"),
            "SSE body should contain tool_calls: {}",
            &body[..body.len().min(500)]
        );
        assert!(body.contains("[DONE]"), "SSE should end with [DONE]");

        // Should contain the tool name and arguments
        assert!(body.contains("Bash"), "SSE should contain tool name 'Bash'");
        assert!(body.contains("echo hello"), "SSE should contain arguments");

        // Should NOT contain content deltas (tool_calls mode has no content)
        // The finish_reason should be "tool_calls" not "stop"
        assert!(
            body.contains("\"finish_reason\":\"tool_calls\""),
            "SSE should have finish_reason: tool_calls"
        );
    }

    /// Test: mock/tool-call with non-existent conversation returns 409.
    #[tokio::test]
    async fn test_tool_call_no_active_connection() {
        let app = test_app();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        let client = reqwest::Client::new();

        // Trigger tool call without an active SSE connection
        let resp = client
            .post(format!("http://{}/v1/mock/tool-call", addr))
            .json(&json!({
                "agent_id": "agt_demo_codex",
                "tool_name": "Bash",
                "arguments": {"command": "ls"}
            }))
            .send()
            .await
            .unwrap();

        // Should be 409 (no pending connection) or 404 (no conversation)
        let status = resp.status();
        assert!(
            status == reqwest::StatusCode::CONFLICT || status == reqwest::StatusCode::NOT_FOUND,
            "Expected 409 or 404, got {}",
            status
        );
    }
}
