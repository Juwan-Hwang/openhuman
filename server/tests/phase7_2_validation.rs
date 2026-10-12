//! Phase 7.2 — Real Agent Compatibility Validation
//!
//! Tests that `AgentProfile::extract()` correctly processes real observation
//! data from Phase 8 (WorkBuddy, Claude Code, Trae).
//!
//! The test fixtures below are derived from real `POST /v1/chat/completions`
//! requests captured by the observation middleware. System prompts are
//! truncated to their first identifying line; tool schemas are preserved
//! verbatim. Headers are sanitized per the observation fixtures.
//!
//! # Test Coverage
//!
//! | Test | Agent | Validates |
//! |------|-------|-----------|
//! | `test_claude_code_profile_extraction` | Claude Code | 3 tools, cc_version detection, system prompt |
//! | `test_workbuddy_profile_extraction` | WorkBuddy | 3 tools (sample), Stainless SDK detection |
//! | `test_trae_profile_extraction` | Trae | 3 tools (sample), hertz detection |
//! | `test_tools_empty_does_not_overwrite` | Regression | tools=[] preserves existing capabilities |
//! | `test_agent_capability_isolation` | Regression | different agent_ids don't share capabilities |
//! | `test_upsert_idempotent` | Regression | repeated requests produce same capabilities |
//! | `test_role_tool_message_parsed` | Regression | role=tool messages deserialize correctly |
//! | `test_context_extraction_all_agents` | Context | system_prompt/model/runtime for all 3 agents |

use axum::http::HeaderMap;
use serde_json::json;

use openhuman_server::openai_compat::{ChatCompletionRequest, ChatRole};
use openhuman_server::profile::{extract_capabilities, AgentProfile, ClientType};

// ── Test Fixtures (derived from Phase 8 observation data) ──

/// Build a Claude Code request fixture.
///
/// Source: `2026-08-24-153406-99d.json` (main conversation request)
/// - 3 tools: Bash, Edit, Read
/// - system prompt: `x-anthropic-billing-header: cc_version=2.1.241.081`
/// - No User-Agent header
fn claude_code_request() -> serde_json::Value {
    json!({
        "model": "openhuman-human",
        "messages": [
            {
                "role": "system",
                "content": "x-anthropic-billing-header: cc_version=2.1.241.081; cc_entrypoint=sdk-cli;\nYou are a Claude agent, built on Anthropic's Claude Agent SDK.\nCWD: E:\\openhuman\nDate: 2026-08-24"
            },
            {
                "role": "user",
                "content": "<system-reminder>\nAs you answer the user's questions, you can use the following context:\n# currentDate\nToday's date is 2026-08-24.\n</system-reminder>\n\nHello! What are you?"
            }
        ],
        "stream": true,
        "max_tokens": 32000,
        "stream_options": {"include_usage": true},
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "Bash",
                    "description": "execute shell commands",
                    "parameters": {
                        "$schema": "https://json-schema.org/draft/2020-12/schema",
                        "additionalProperties": false,
                        "properties": {
                            "command": {"description": "The command to execute", "type": "string"},
                            "timeout": {"description": "Optional timeout in milliseconds (max 600000)", "type": "number"}
                        },
                        "required": ["command"],
                        "type": "object"
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "Edit",
                    "description": "modify file contents in place",
                    "parameters": {
                        "$schema": "https://json-schema.org/draft/2020-12/schema",
                        "additionalProperties": false,
                        "properties": {
                            "file_path": {"description": "The absolute path to the file to modify", "type": "string"},
                            "old_string": {"description": "The text to replace", "type": "string"},
                            "new_string": {"description": "The text to replace it with", "type": "string"}
                        },
                        "required": ["file_path", "old_string", "new_string"],
                        "type": "object"
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "Read",
                    "description": "read files, images, PDFs, notebooks",
                    "parameters": {
                        "$schema": "https://json-schema.org/draft/2020-12/schema",
                        "additionalProperties": false,
                        "properties": {
                            "file_path": {"description": "The absolute path to the file to read", "type": "string"}
                        },
                        "required": ["file_path"],
                        "type": "object"
                    }
                }
            }
        ]
    })
}

/// Build a WorkBuddy request fixture.
///
/// Source: `2026-08-24-151554-d4a.json`
/// - 22 tools total (we sample 3 for test brevity)
/// - system prompt: `This conversation is powered by test`
/// - User-Agent: `WorkBuddy/5.3.14 WorkBuddy/5.3.14 CLI/2.115.0`
/// - x-ide-name: WorkBuddy
fn workbuddy_request() -> serde_json::Value {
    json!({
        "model": "test",
        "messages": [
            {
                "role": "system",
                "content": "This conversation is powered by test\r\n\r\nYour main goal is to follow the USER's instructions at each message, denoted by the <user_query> tag."
            },
            {
                "role": "user",
                "content": [{"type": "text", "text": "<user_query>你好</user_query>"}]
            }
        ],
        "stream": true,
        "temperature": 1,
        "reasoning_effort": "high",
        "stream_options": {"include_usage": true},
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "Bash",
                    "description": "Execute bash commands",
                    "parameters": {
                        "$schema": "https://json-schema.org/draft/2020-12/schema",
                        "additionalProperties": false,
                        "properties": {
                            "command": {"description": "The bash command to execute", "type": "string"}
                        },
                        "required": ["command"],
                        "type": "object"
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "Read",
                    "description": "Read a file from the local filesystem",
                    "parameters": {
                        "additionalProperties": false,
                        "properties": {
                            "file_path": {"description": "The absolute path to the file to read", "type": "string"}
                        },
                        "required": ["file_path"],
                        "type": "object"
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "TaskCreate",
                    "description": "Create a new task",
                    "parameters": {
                        "additionalProperties": false,
                        "properties": {
                            "task_name": {"description": "The name of the task", "type": "string"}
                        },
                        "required": ["task_name"],
                        "type": "object"
                    }
                }
            }
        ]
    })
}

/// Build a Trae request fixture.
///
/// Source: `2026-08-24-153728-2e0.json`
/// - ~20 tools total (we sample 3 for test brevity)
/// - system prompt: `You are a powerful assistant mastering all kinds of tasks operating in TraeWork`
/// - User-Agent: hertz
fn trae_request() -> serde_json::Value {
    json!({
        "model": "openhuman-human",
        "messages": [
            {
                "role": "system",
                "content": "You are a powerful assistant mastering all kinds of tasks operating in TraeWork, powered by a proprietary model internally developed by the Trae team."
            },
            {
                "role": "user",
                "content": [{"type": "text", "text": "<user_input>\n这里是trae，第一条测试\n</user_input>"}]
            }
        ],
        "stream": true,
        "max_tokens": 16000,
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "Task",
                    "description": "Launch a new agent to handle complex, multi-step tasks autonomously.",
                    "parameters": {
                        "properties": {
                            "description": {"type": "string"},
                            "query": {"type": "string"},
                            "subagent_type": {"type": "string"}
                        },
                        "required": ["description", "query", "subagent_type"],
                        "type": "object"
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "Read",
                    "description": "Reads a file from the local filesystem.",
                    "parameters": {
                        "properties": {
                            "file_path": {"description": "The absolute path to the file to read", "type": "string"}
                        },
                        "required": ["file_path"],
                        "type": "object"
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "TodoWrite",
                    "description": "Create and manage a structured task list",
                    "parameters": {
                        "properties": {
                            "todos": {"type": "array"}
                        },
                        "required": ["todos"],
                        "type": "object"
                    }
                }
            }
        ]
    })
}

/// Build Claude Code headers (no User-Agent, no custom headers).
fn claude_code_headers() -> HeaderMap {
    let mut h = HeaderMap::new();
    h.insert("accept", "text/event-stream".parse().unwrap());
    h.insert("content-type", "application/json".parse().unwrap());
    h.insert("connection", "keep-alive".parse().unwrap());
    h
}

/// Build WorkBuddy headers (Stainless SDK + x-ide-name).
fn workbuddy_headers() -> HeaderMap {
    let mut h = HeaderMap::new();
    h.insert("accept", "application/json".parse().unwrap());
    h.insert("content-type", "application/json".parse().unwrap());
    h.insert(
        "user-agent",
        "WorkBuddy/5.3.14 WorkBuddy/5.3.14 CLI/2.115.0"
            .parse()
            .unwrap(),
    );
    h.insert("x-ide-name", "WorkBuddy".parse().unwrap());
    h.insert("x-stainless-package-version", "6.25.0".parse().unwrap());
    h.insert("x-stainless-lang", "js".parse().unwrap());
    h.insert("x-stainless-runtime", "node".parse().unwrap());
    h.insert("x-stainless-runtime-version", "v22.21.1".parse().unwrap());
    h
}

/// Build Trae headers (hertz + acl-token).
fn trae_headers() -> HeaderMap {
    let mut h = HeaderMap::new();
    h.insert("accept", "*/*".parse().unwrap());
    h.insert("content-type", "application/json".parse().unwrap());
    h.insert("user-agent", "hertz".parse().unwrap());
    h.insert(
        "x-model-provider",
        "custom_openai_compatible".parse().unwrap(),
    );
    h
}

/// Parse a JSON value into a ChatCompletionRequest.
fn parse_req(json: &serde_json::Value) -> ChatCompletionRequest {
    serde_json::from_value(json.clone()).expect("Failed to parse request")
}

// ════════════════════════════════════════════════════════════
// Task 1: Observation Replay — Profile Extraction
// ════════════════════════════════════════════════════════════

#[test]
fn test_claude_code_profile_extraction() {
    let req = parse_req(&claude_code_request());
    let headers = claude_code_headers();
    let profile = AgentProfile::extract(&headers, &req, "agt_claude_code");

    // Agent ID
    assert_eq!(profile.agent_id, "agt_claude_code");

    // Client type — detected from system prompt `cc_version=`
    assert_eq!(profile.client_type, ClientType::ClaudeCode);

    // Model
    assert_eq!(profile.model, Some("openhuman-human".to_string()));

    // System prompt — should contain cc_version
    let sp = profile.system_prompt.as_ref().expect("system prompt");
    assert!(sp.contains("cc_version=2.1.241.081"));
    assert!(sp.contains("Claude Agent SDK"));

    // Runtime — no User-Agent, no Stainless headers
    assert!(profile.runtime.user_agent.is_none());
    assert!(profile.runtime.stainless_version.is_none());
    assert_eq!(
        profile.runtime.detected_framework,
        Some("Claude Agent SDK".to_string())
    );

    // Capabilities — 3 tools
    assert_eq!(profile.capabilities.len(), 3);
    let names: Vec<&str> = profile.capabilities.iter().map(|c| c.id.as_str()).collect();
    assert_eq!(names, vec!["Bash", "Edit", "Read"]);
}

#[test]
fn test_workbuddy_profile_extraction() {
    let req = parse_req(&workbuddy_request());
    let headers = workbuddy_headers();
    let profile = AgentProfile::extract(&headers, &req, "agt_workbuddy");

    // Client type — detected from x-ide-name + User-Agent
    assert_eq!(profile.client_type, ClientType::WorkBuddy);

    // Model — WorkBuddy sends "test" as model
    assert_eq!(profile.model, Some("test".to_string()));

    // System prompt
    let sp = profile.system_prompt.as_ref().expect("system prompt");
    assert!(sp.contains("powered by test"));
    assert!(sp.contains("<user_query>"));

    // Runtime — Stainless SDK detected
    assert_eq!(
        profile.runtime.user_agent.as_deref(),
        Some("WorkBuddy/5.3.14 WorkBuddy/5.3.14 CLI/2.115.0")
    );
    assert_eq!(
        profile.runtime.stainless_version,
        Some("6.25.0".to_string())
    );
    assert_eq!(profile.runtime.ide_name, Some("WorkBuddy".to_string()));

    // Capabilities — 3 tools in fixture
    assert_eq!(profile.capabilities.len(), 3);
    let names: Vec<&str> = profile.capabilities.iter().map(|c| c.id.as_str()).collect();
    assert_eq!(names, vec!["Bash", "Read", "TaskCreate"]);
}

#[test]
fn test_trae_profile_extraction() {
    let req = parse_req(&trae_request());
    let headers = trae_headers();
    let profile = AgentProfile::extract(&headers, &req, "agt_trae");

    // Client type — detected from User-Agent: hertz
    assert_eq!(profile.client_type, ClientType::Trae);

    // Model
    assert_eq!(profile.model, Some("openhuman-human".to_string()));

    // System prompt
    let sp = profile.system_prompt.as_ref().expect("system prompt");
    assert!(sp.contains("TraeWork"));
    assert!(sp.contains("powered by a proprietary model"));

    // Runtime — hertz framework
    assert_eq!(profile.runtime.user_agent, Some("hertz".to_string()));
    assert!(profile.runtime.stainless_version.is_none());
    assert_eq!(
        profile.runtime.detected_framework,
        Some("Hertz (ByteDance)".to_string())
    );

    // Capabilities — 3 tools in fixture
    assert_eq!(profile.capabilities.len(), 3);
    let names: Vec<&str> = profile.capabilities.iter().map(|c| c.id.as_str()).collect();
    assert!(names.contains(&"Task"));
    assert!(names.contains(&"Read"));
    assert!(names.contains(&"TodoWrite"));
}

// ════════════════════════════════════════════════════════════
// Task 2: Capability Extraction — function.name/description/parameters
// ════════════════════════════════════════════════════════════

#[test]
fn test_claude_code_capability_fields() {
    let req = parse_req(&claude_code_request());
    let headers = claude_code_headers();
    let profile = AgentProfile::extract(&headers, &req, "agt_cc");

    // Verify each capability has correct name, description, parameters
    let bash = profile
        .capabilities
        .iter()
        .find(|c| c.id == "Bash")
        .unwrap();
    assert_eq!(bash.name, "Bash");
    assert_eq!(bash.description, Some("execute shell commands".to_string()));
    assert!(bash.input_schema.is_some());
    let schema = bash.input_schema.as_ref().unwrap();
    assert_eq!(schema["type"], "object");
    assert!(schema["properties"]["command"]["type"].is_string());
    assert_eq!(schema["required"][0], "command");
    assert_eq!(bash.category, Some("terminal".to_string()));

    let edit = profile
        .capabilities
        .iter()
        .find(|c| c.id == "Edit")
        .unwrap();
    assert_eq!(
        edit.description,
        Some("modify file contents in place".to_string())
    );
    assert_eq!(edit.category, Some("filesystem".to_string()));
    let edit_schema = edit.input_schema.as_ref().unwrap();
    assert_eq!(edit_schema["required"][0], "file_path");

    let read = profile
        .capabilities
        .iter()
        .find(|c| c.id == "Read")
        .unwrap();
    assert_eq!(
        read.description,
        Some("read files, images, PDFs, notebooks".to_string())
    );
    assert_eq!(read.category, Some("filesystem".to_string()));
}

#[test]
fn test_workbuddy_capability_fields() {
    let req = parse_req(&workbuddy_request());
    let headers = workbuddy_headers();
    let profile = AgentProfile::extract(&headers, &req, "agt_wb");

    let bash = profile
        .capabilities
        .iter()
        .find(|c| c.id == "Bash")
        .unwrap();
    assert_eq!(bash.description, Some("Execute bash commands".to_string()));
    assert_eq!(bash.category, Some("terminal".to_string()));

    let task_create = profile
        .capabilities
        .iter()
        .find(|c| c.id == "TaskCreate")
        .unwrap();
    assert_eq!(
        task_create.description,
        Some("Create a new task".to_string())
    );
    assert_eq!(task_create.category, Some("task_management".to_string()));
    let tc_schema = task_create.input_schema.as_ref().unwrap();
    assert_eq!(tc_schema["properties"]["task_name"]["type"], "string");
}

#[test]
fn test_trae_capability_fields() {
    let req = parse_req(&trae_request());
    let headers = trae_headers();
    let profile = AgentProfile::extract(&headers, &req, "agt_trae");

    let task = profile
        .capabilities
        .iter()
        .find(|c| c.id == "Task")
        .unwrap();
    assert!(task
        .description
        .as_ref()
        .unwrap()
        .contains("Launch a new agent"));
    assert_eq!(task.category, Some("subagent".to_string()));
    let task_schema = task.input_schema.as_ref().unwrap();
    assert_eq!(task_schema["required"][0], "description");

    let todo = profile
        .capabilities
        .iter()
        .find(|c| c.id == "TodoWrite")
        .unwrap();
    assert_eq!(todo.category, Some("task_management".to_string()));
}

// ════════════════════════════════════════════════════════════
// Task 3: Context Verification
// ════════════════════════════════════════════════════════════

#[test]
fn test_context_extraction_all_agents() {
    // Claude Code
    {
        let req = parse_req(&claude_code_request());
        let headers = claude_code_headers();
        let profile = AgentProfile::extract(&headers, &req, "agt_cc");
        let ctx = profile.to_context();

        assert_eq!(ctx.agent_id, "agt_cc");
        assert!(ctx.system_prompt.as_ref().unwrap().contains("cc_version="));
        assert_eq!(ctx.model.unwrap()["name"], "openhuman-human");
        let runtime = ctx.runtime.unwrap();
        assert!(runtime["detected_framework"]
            .as_str()
            .unwrap()
            .contains("Claude Agent SDK"));
    }

    // WorkBuddy
    {
        let req = parse_req(&workbuddy_request());
        let headers = workbuddy_headers();
        let profile = AgentProfile::extract(&headers, &req, "agt_wb");
        let ctx = profile.to_context();

        assert_eq!(ctx.agent_id, "agt_wb");
        assert!(ctx
            .system_prompt
            .as_ref()
            .unwrap()
            .contains("powered by test"));
        assert_eq!(ctx.model.unwrap()["name"], "test");
        let runtime = ctx.runtime.unwrap();
        assert_eq!(
            runtime["user_agent"].as_str().unwrap(),
            "WorkBuddy/5.3.14 WorkBuddy/5.3.14 CLI/2.115.0"
        );
        assert_eq!(runtime["stainless_version"].as_str().unwrap(), "6.25.0");
        assert_eq!(runtime["ide_name"].as_str().unwrap(), "WorkBuddy");
    }

    // Trae
    {
        let req = parse_req(&trae_request());
        let headers = trae_headers();
        let profile = AgentProfile::extract(&headers, &req, "agt_trae");
        let ctx = profile.to_context();

        assert_eq!(ctx.agent_id, "agt_trae");
        assert!(ctx.system_prompt.as_ref().unwrap().contains("TraeWork"));
        assert_eq!(ctx.model.unwrap()["name"], "openhuman-human");
        let runtime = ctx.runtime.unwrap();
        assert_eq!(runtime["user_agent"].as_str().unwrap(), "hertz");
        assert_eq!(
            runtime["detected_framework"].as_str().unwrap(),
            "Hertz (ByteDance)"
        );
    }
}

// ════════════════════════════════════════════════════════════
// Task 4: Regression Tests
// ════════════════════════════════════════════════════════════

/// Regression: `tools: []` should not produce capabilities, and calling
/// `extract_capabilities` with an empty array returns an empty vec
/// (which the handler checks before overwriting).
#[test]
fn test_tools_empty_does_not_overwrite() {
    // Simulate a request with tools: [] (like Claude Code's title request)
    let json = json!({
        "model": "openhuman-human",
        "messages": [{"role": "user", "content": "hello"}],
        "stream": true,
        "tools": []
    });
    let req: ChatCompletionRequest = serde_json::from_value(json).unwrap();
    let caps = extract_capabilities(req.tools.as_ref());
    assert!(
        caps.is_empty(),
        "Empty tools[] should produce zero capabilities"
    );

    // The handler checks `!capabilities.is_empty()` before calling
    // `set_capabilities`, so existing capabilities are preserved.
    // This is the Phase 7.1.1 non-destructive upsert guarantee.
}

/// Regression: Different agent_ids produce isolated capability sets.
#[test]
fn test_agent_capability_isolation() {
    let cc_req = parse_req(&claude_code_request());
    let wb_req = parse_req(&workbuddy_request());

    let cc_headers = claude_code_headers();
    let wb_headers = workbuddy_headers();

    let cc_profile = AgentProfile::extract(&cc_headers, &cc_req, "agt_cc");
    let wb_profile = AgentProfile::extract(&wb_headers, &wb_req, "agt_wb");

    // Different agent IDs
    assert_ne!(cc_profile.agent_id, wb_profile.agent_id);

    // Both have Bash, but different additional tools
    let cc_names: Vec<&str> = cc_profile
        .capabilities
        .iter()
        .map(|c| c.id.as_str())
        .collect();
    let wb_names: Vec<&str> = wb_profile
        .capabilities
        .iter()
        .map(|c| c.id.as_str())
        .collect();

    assert!(cc_names.contains(&"Bash"));
    assert!(cc_names.contains(&"Edit"));
    assert!(cc_names.contains(&"Read"));

    assert!(wb_names.contains(&"Bash"));
    assert!(wb_names.contains(&"Read"));
    assert!(wb_names.contains(&"TaskCreate"));

    // WorkBuddy has TaskCreate, Claude Code doesn't
    assert!(!cc_names.contains(&"TaskCreate"));
    // Claude Code has Edit, WorkBuddy fixture doesn't
    assert!(!wb_names.contains(&"Edit"));
}

/// Regression: Repeated extraction from the same request is idempotent.
#[test]
fn test_upsert_idempotent() {
    let req = parse_req(&claude_code_request());
    let headers = claude_code_headers();

    let profile1 = AgentProfile::extract(&headers, &req, "agt_cc");
    let profile2 = AgentProfile::extract(&headers, &req, "agt_cc");

    // Same agent_id
    assert_eq!(profile1.agent_id, profile2.agent_id);

    // Same number of capabilities
    assert_eq!(profile1.capabilities.len(), profile2.capabilities.len());

    // Same tool names in same order
    let names1: Vec<&str> = profile1
        .capabilities
        .iter()
        .map(|c| c.id.as_str())
        .collect();
    let names2: Vec<&str> = profile2
        .capabilities
        .iter()
        .map(|c| c.id.as_str())
        .collect();
    assert_eq!(names1, names2);

    // Same descriptions
    for (c1, c2) in profile1
        .capabilities
        .iter()
        .zip(profile2.capabilities.iter())
    {
        assert_eq!(c1.id, c2.id);
        assert_eq!(c1.description, c2.description);
        assert_eq!(c1.input_schema, c2.input_schema);
    }
}

/// Regression: `role: "tool"` messages deserialize correctly with
/// `tool_call_id` and content.
#[test]
fn test_role_tool_message_parsed() {
    let json = json!({
        "model": "openhuman-human",
        "messages": [
            {
                "role": "user",
                "content": "Please list files"
            },
            {
                "role": "assistant",
                "content": null,
                "tool_calls": [{
                    "id": "call_abc123",
                    "type": "function",
                    "function": {
                        "name": "Bash",
                        "arguments": "{\"command\": \"ls -la\"}"
                    }
                }]
            },
            {
                "role": "tool",
                "content": "total 42\ndrwxr-xr-x  3 root root 4096 Aug 24 15:00 .",
                "tool_call_id": "call_abc123"
            }
        ],
        "stream": true
    });

    let req: ChatCompletionRequest = serde_json::from_value(json).unwrap();

    // 3 messages
    assert_eq!(req.messages.len(), 3);

    // Message 0: user
    assert_eq!(req.messages[0].role, ChatRole::User);

    // Message 1: assistant with tool_calls
    assert_eq!(req.messages[1].role, ChatRole::Assistant);
    assert!(req.messages[1].tool_calls.is_some());
    let tool_calls = req.messages[1].tool_calls.as_ref().unwrap();
    assert_eq!(tool_calls[0]["id"], "call_abc123");
    assert_eq!(tool_calls[0]["function"]["name"], "Bash");

    // Message 2: tool result
    assert_eq!(req.messages[2].role, ChatRole::Tool);
    assert_eq!(
        req.messages[2].tool_call_id,
        Some("call_abc123".to_string())
    );
    assert!(req.messages[2].content.to_text().contains("total 42"));
}

// ════════════════════════════════════════════════════════════
// Task 5: Non-standard fields don't break parsing
// ════════════════════════════════════════════════════════════

/// Verify that non-standard fields (reasoning_effort, temperature)
/// are accepted without error.
#[test]
fn test_non_standard_fields_accepted() {
    let json = json!({
        "model": "test",
        "messages": [{"role": "user", "content": "hi"}],
        "stream": true,
        "temperature": 1,
        "reasoning_effort": "high",
        "stream_options": {"include_usage": true},
        "max_tokens": 32000
    });

    let req: ChatCompletionRequest = serde_json::from_value(json).unwrap();
    assert_eq!(req.temperature, Some(1.0));
    assert_eq!(req.reasoning_effort, Some("high".to_string()));
    assert_eq!(req.stream_options, Some(json!({"include_usage": true})));
    assert_eq!(req.max_tokens, Some(32000));
}

/// Verify that a request with no tools at all (missing field) works.
#[test]
fn test_no_tools_field() {
    let json = json!({
        "model": "human",
        "messages": [{"role": "user", "content": "hello"}],
        "stream": false
    });

    let req: ChatCompletionRequest = serde_json::from_value(json).unwrap();
    assert!(req.tools.is_none());

    let caps = extract_capabilities(req.tools.as_ref());
    assert!(caps.is_empty());
}
