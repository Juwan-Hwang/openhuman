//! OpenHuman Server — library crate.
//!
//! All modules are declared here so integration tests can access
//! `openhuman_server::build_router` etc.

pub mod api;
pub mod async_reply;
pub mod auth;
pub mod crypto;
pub mod model;
pub mod normalize;
pub mod notification;
pub mod observation;
pub mod openai_compat;
pub mod profile;
pub mod rooms;
pub mod seat;
pub mod session;
pub mod state;
pub mod storage;
pub mod ws;

use axum::middleware::from_fn_with_state;
use axum::routing::{delete, get, post};
use axum::Router;
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::trace::TraceLayer;

use crate::storage::AppState;

/// Maximum inbound request body, in bytes.
///
/// Agent requests routinely reach hundreds of KB (system prompts + tool
/// schemas + replayed history), so the cap is generous — its job is to
/// stop absurd payloads from pinning memory, not to police normal traffic.
/// Overridable via `OPENHUMAN_MAX_BODY_BYTES`.
fn max_body_bytes() -> usize {
    std::env::var("OPENHUMAN_MAX_BODY_BYTES")
        .ok()
        .and_then(|v| v.trim().parse::<usize>().ok())
        .filter(|v| *v > 0)
        .unwrap_or(8 * 1024 * 1024)
}

/// Maximum concurrent in-flight requests.
///
/// Each open turn pins a connection for as long as the human takes to
/// answer; an unbounded server lets one caller starve the rest.
/// Overridable via `OPENHUMAN_MAX_CONCURRENCY`.
fn max_concurrency() -> usize {
    std::env::var("OPENHUMAN_MAX_CONCURRENCY")
        .ok()
        .and_then(|v| v.trim().parse::<usize>().ok())
        .filter(|v| *v > 0)
        .unwrap_or(256)
}

/// Build the Axum router with all routes.
///
/// Routes:
///   - `GET  /health`, `GET /healthz`    — health check
///   - `GET  /ws`                        — WebSocket Human Gateway
///   - `POST /v1/chat/completions`       — OpenAI-compatible API (auth + observation)
///   - `GET  /v1/replies/:invocation_id`— async reply polling (auth)
///   - `POST /v1/mock/human-reply`       — Mock human reply (dev/test)
///   - `POST /v1/mock/end-turn`          — Close an open streaming turn (dev/test)
///
/// The `/v1/chat/completions` route has an observation layer that
/// records the raw request to `observations/` for analysis.
///
/// Layer order (outer → inner):
///   1. TraceLayer (HTTP tracing)
///   2. Observation layer (raw request capture)
///   3. Auth layer (API key validation)
///   4. Handler (chat_completions)
pub fn build_router(state: AppState) -> Router {
    let protected = Router::new()
        .route("/v1/chat/completions", post(api::openai::chat_completions))
        // Same pipeline, other wires: Anthropic Messages (Claude Code) and
        // OpenAI Responses (Codex CLI).
        .route("/v1/messages", post(api::adapters::messages))
        .route(
            "/v1/messages/count_tokens",
            post(api::adapters::count_tokens),
        )
        .route("/v1/responses", post(api::adapters::responses))
        .route(
            "/v1/files",
            post(api::files::upload)
                .get(api::files::list)
                .layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/files/:file_id",
            get(api::files::get_meta).delete(api::files::delete),
        )
        .route("/v1/files/:file_id/content", get(api::files::content))
        .route("/v1/uploads", post(api::uploads::create))
        .route(
            "/v1/uploads/:upload_id/parts",
            post(api::uploads::add_part).layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/uploads/:upload_id/complete",
            post(api::uploads::complete),
        )
        .route("/v1/uploads/:upload_id/cancel", post(api::uploads::cancel))
        .route(
            "/v1/batches",
            post(api::batches::create).get(api::batches::list),
        )
        .route("/v1/batches/:batch_id", get(api::batches::retrieve))
        .route("/v1/batches/:batch_id/cancel", post(api::batches::cancel))
        .route(
            "/v1/vector_stores",
            post(api::vector_stores::create).get(api::vector_stores::list),
        )
        .route(
            "/v1/vector_stores/:store_id",
            get(api::vector_stores::retrieve)
                .post(api::vector_stores::modify)
                .delete(api::vector_stores::delete),
        )
        .route(
            "/v1/vector_stores/:store_id/files",
            post(api::vector_stores::add_file).get(api::vector_stores::list_files),
        )
        .route(
            "/v1/vector_stores/:store_id/files/:file_id",
            get(api::vector_stores::get_file)
                .post(api::vector_stores::update_file)
                .delete(api::vector_stores::delete_file),
        )
        .route(
            "/v1/vector_stores/:store_id/files/:file_id/content",
            get(api::vector_stores::file_content),
        )
        .route(
            "/v1/vector_stores/:store_id/file_batches",
            post(api::vector_stores::create_batch),
        )
        .route(
            "/v1/vector_stores/:store_id/file_batches/:batch_id",
            get(api::vector_stores::get_batch_route).post(api::vector_stores::cancel_batch),
        )
        .route(
            "/v1/vector_stores/:store_id/file_batches/:batch_id/files",
            get(api::vector_stores::batch_files),
        )
        .route(
            "/v1/vector_stores/:store_id/search",
            post(api::vector_stores::search),
        )
        .route(
            "/v1/assistants",
            post(api::assistants::create_assistant).get(api::assistants::list_assistants),
        )
        .route(
            "/v1/assistants/:id",
            get(api::assistants::get_assistant)
                .post(api::assistants::update_assistant)
                .delete(api::assistants::delete_assistant),
        )
        .route("/v1/threads", post(api::assistants::create_thread))
        .route(
            "/v1/threads/runs",
            post(api::assistants::create_thread_and_run),
        )
        .route(
            "/v1/threads/:id",
            get(api::assistants::get_thread)
                .post(api::assistants::update_thread)
                .delete(api::assistants::delete_thread),
        )
        .route(
            "/v1/threads/:id/messages",
            post(api::assistants::create_message).get(api::assistants::list_messages),
        )
        .route(
            "/v1/threads/:id/messages/:message_id",
            get(api::assistants::get_message)
                .post(api::assistants::update_message)
                .delete(api::assistants::delete_message),
        )
        .route(
            "/v1/threads/:id/runs",
            post(api::assistants::create_run).get(api::assistants::list_runs),
        )
        .route(
            "/v1/threads/:id/runs/:run_id",
            get(api::assistants::get_run_route).post(api::assistants::update_run),
        )
        .route(
            "/v1/threads/:id/runs/:run_id/cancel",
            post(api::assistants::cancel_run),
        )
        .route(
            "/v1/threads/:id/runs/:run_id/submit_tool_outputs",
            post(api::assistants::submit_tool_outputs),
        )
        .route(
            "/v1/threads/:id/runs/:run_id/steps",
            get(api::assistants::list_steps),
        )
        .route(
            "/v1/threads/:id/runs/:run_id/steps/:step_id",
            get(api::assistants::get_step),
        )
        .route("/v1/models", get(list_models))
        .route("/v1/models/:model_id", get(get_model))
        // A base URL configured as `.../v1` by a client that appends `/v1`
        // itself (Copilot's Anthropic provider, several SDKs) lands here.
        .route(
            "/v1/v1/chat/completions",
            post(api::openai::chat_completions),
        )
        .route("/v1/v1/messages", post(api::adapters::messages))
        .route(
            "/v1/v1/messages/count_tokens",
            post(api::adapters::count_tokens),
        )
        .route("/v1/v1/responses", post(api::adapters::responses))
        .route("/v1/v1/models", get(list_models))
        .route("/v1/v1/models/:model_id", get(get_model))
        .route("/v1/tokenizers", get(list_tokenizers))
        // The other OpenAI endpoints: each request is a task the seat
        // answers (see `api/task.rs`).
        .route("/v1/images/generations", post(api::images::generations))
        .route("/v1/v1/images/generations", post(api::images::generations))
        .route(
            "/v1/images/edits",
            post(api::images::edits).layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/v1/images/edits",
            post(api::images::edits).layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route("/v1/completions", post(api::completions::completions))
        .route("/v1/v1/completions", post(api::completions::completions))
        .route("/v1/audio/speech", post(api::audio::speech))
        .route("/v1/v1/audio/speech", post(api::audio::speech))
        .route(
            "/v1/audio/transcriptions",
            post(api::audio::transcriptions).layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/v1/audio/transcriptions",
            post(api::audio::transcriptions).layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/audio/translations",
            post(api::audio::translations).layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/v1/audio/translations",
            post(api::audio::translations).layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/audio/voices",
            post(api::library::create_voice)
                .get(api::library::list_voices)
                .layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/audio/voices/:id",
            get(api::library::get_voice).delete(api::library::delete_voice),
        )
        .route(
            "/v1/audio/voice_consents",
            post(api::library::create_consent)
                .get(api::library::list_consents)
                .layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/audio/voice_consents/:id",
            get(api::library::get_consent)
                .post(api::library::update_consent)
                .delete(api::library::delete_consent),
        )
        .route(
            "/v1/skills",
            post(api::library::create_skill)
                .get(api::library::list_skills)
                .layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/skills/:id",
            get(api::library::retrieve_skill)
                .post(api::library::update_skill)
                .delete(api::library::delete_skill),
        )
        .route("/v1/skills/:id/content", get(api::library::skill_content))
        .route(
            "/v1/skills/:id/versions",
            post(api::library::create_version)
                .get(api::library::list_versions)
                .layer(axum::extract::DefaultBodyLimit::disable()),
        )
        .route(
            "/v1/skills/:id/versions/:version",
            get(api::library::get_version).delete(api::library::delete_version),
        )
        .route(
            "/v1/skills/:id/versions/:version/content",
            get(api::library::version_content),
        )
        // Companion to async mode: poll for a human's reply without
        // holding the original request open.
        // axum 0.7 path-parameter syntax is `:name` — `{name}` would be
        // registered as a literal segment and match nothing.
        .route("/v1/replies/:invocation_id", get(api::replies::get_reply))
        // History. The backlog on connect deliberately carries only
        // undelivered messages, so a client that wants the past has to ask
        // for it — replaying everything on every reconnect meant the human
        // watched conversations they had already answered arrive again.
        .route("/v1/conversations", get(api::history::list_conversations))
        .route(
            "/v1/conversations/:conversation_id/messages",
            get(api::history::list_messages),
        )
        // Trash: delete moves a conversation aside, restore brings it back,
        // and only the permanent route actually destroys anything.
        .route(
            "/v1/conversations/:conversation_id",
            delete(api::history::delete_conversation),
        )
        // Keep a conversation: messages live in memory unless saved.
        .route(
            "/v1/conversations/:conversation_id/save",
            post(api::history::save_conversation),
        )
        .route(
            "/v1/conversations/:conversation_id/restore",
            post(api::history::restore_conversation),
        )
        .route(
            "/v1/conversations/:conversation_id/permanent",
            delete(api::history::delete_conversation_permanent),
        )
        // The seeded agent name is rarely what the human calls it.
        // The Agents API (beta): agents, sessions with turns, items and
        // an event stream. PATCH on /v1/agents/:agent_id stays with
        // history::rename_agent (seat-agent identities in history).
        .route(
            "/v1/agents",
            post(api::agents::create_agent).get(api::agents::list_agents),
        )
        .route(
            "/v1/agents/:agent_id",
            get(api::agents::get_agent)
                .post(api::agents::update_agent)
                .delete(api::agents::delete_agent)
                .patch(api::history::rename_agent),
        )
        .route(
            "/v1/agents/sessions",
            post(api::agents::create_session).get(api::agents::list_sessions),
        )
        .route(
            "/v1/agents/sessions/:id",
            get(api::agents::get_session)
                .post(api::agents::update_session)
                .delete(api::agents::delete_session),
        )
        .route(
            "/v1/agents/sessions/:id/events",
            post(api::agents::create_events).get(api::agents::stream_events),
        )
        .route(
            "/v1/agents/sessions/:id/items",
            get(api::agents::list_items),
        )
        .route(
            "/v1/agents/sessions/:id/turns",
            get(api::agents::list_turns),
        )
        .route(
            "/v1/agents/sessions/:id/turns/:turn",
            get(api::agents::get_turn),
        )
        .route(
            "/v1/agents/sessions/:id/turns/:turn/items",
            get(api::agents::list_turn_items),
        )
        .route(
            "/v1/agents/sessions/:id/traces",
            get(api::agents::empty_list),
        )
        .route(
            "/v1/agents/sessions/:id/artifacts",
            get(api::agents::empty_list),
        )
        .route(
            "/v1/agents/sessions/:id/subagents",
            get(api::agents::empty_list),
        )
        .route(
            "/v1/agents/sessions/:id/artifacts/:art",
            get(api::agents::none_found).delete(api::agents::none_found),
        )
        .route(
            "/v1/agents/sessions/:id/artifacts/:art/content",
            get(api::agents::none_found),
        )
        .route(
            "/v1/agents/sessions/:id/subagents/:sub",
            get(api::agents::none_found),
        )
        .route(
            "/v1/agents/sessions/:id/subagents/:sub/items",
            get(api::agents::none_found),
        )
        .route(
            "/v1/agents/sessions/:id/subagents/:sub/turns",
            get(api::agents::none_found),
        )
        .route(
            "/v1/agents/sessions/:id/subagents/:sub/turns/:turn",
            get(api::agents::none_found),
        )
        .route(
            "/v1/agents/sessions/:id/subagents/:sub/turns/:turn/items",
            get(api::agents::none_found),
        )
        // Agent Seat: the human seat over plain HTTP, for agents that
        // cannot hold a WebSocket (see `seat.rs`).
        .route("/v1/seat/inbox", get(seat::inbox))
        .route("/v1/seat/send", post(seat::send))
        .route("/v1/seat/reply", post(seat::reply))
        .route("/v1/seat/tool-call", post(seat::tool_call))
        .route("/v1/seat/capabilities", get(seat::capabilities))
        .route("/v1/seat/history", get(seat::history))
        .route("/v1/seat/save", post(seat::save))
        .route(
            "/v1/seat/model-name",
            post(seat::model_name).get(seat::model_name_get),
        )
        // Observation runs *inside* auth: only authenticated requests are
        // captured, so an anonymous caller cannot fill the disk.
        .layer(axum::middleware::from_fn(observation::observe_request))
        .layer(from_fn_with_state(state.clone(), auth::require_api_key));

    // Room management routes (design doc §5.1) — responder side, human
    // clients. Registered only while the OPENHUMAN_ROOMS flag is on; the
    // 1:1 surface is untouched either way. The caller ingress
    // `/rooms/:id/v1/*` is registered with them.
    let rooms = if crate::rooms::rooms_enabled() {
        Router::new()
            .route(
                "/v1/rooms",
                post(api::rooms::create_room).get(api::rooms::list_rooms),
            )
            .route(
                "/v1/rooms/:room_id",
                get(api::rooms::get_room).patch(api::rooms::patch_room),
            )
            .route(
                "/v1/rooms/:room_id/invites",
                post(api::rooms::create_invite),
            )
            .route(
                "/v1/rooms/:room_id/invites/:code",
                delete(api::rooms::revoke_invite),
            )
            .route("/v1/invites/:code/accept", post(api::rooms::accept_invite))
            .route("/v1/rooms/:room_id/leave", post(api::rooms::leave_room))
            .route(
                "/v1/rooms/:room_id/members/:pid",
                delete(api::rooms::kick_member),
            )
            .route(
                "/v1/rooms/:room_id/messages",
                get(api::rooms::room_messages),
            )
            .route("/v1/rooms/:room_id/callers", get(api::rooms::room_callers))
            .route(
                "/v1/rooms/:room_id/caller-keys",
                post(api::rooms::create_caller_key),
            )
            // Caller ingress (§5.2): the room prefix carries the same
            // three wires plus the /v1/v1 alias and per-room models.
            .route(
                "/rooms/:room_id/v1/chat/completions",
                post(api::room_ingress::room_chat_completions),
            )
            .route(
                "/rooms/:room_id/v1/v1/chat/completions",
                post(api::room_ingress::room_chat_completions),
            )
            .route(
                "/rooms/:room_id/v1/messages",
                post(api::adapters::room_messages),
            )
            .route(
                "/rooms/:room_id/v1/v1/messages",
                post(api::adapters::room_messages),
            )
            .route(
                "/rooms/:room_id/v1/responses",
                post(api::adapters::room_responses),
            )
            .route(
                "/rooms/:room_id/v1/replies/:invocation_id",
                get(api::replies::room_get_reply),
            )
            .route(
                "/rooms/:room_id/v1/v1/replies/:invocation_id",
                get(api::replies::room_get_reply),
            )
            .route(
                "/rooms/:room_id/v1/v1/responses",
                post(api::adapters::room_responses),
            )
            .route(
                "/rooms/:room_id/v1/models",
                get(api::room_ingress::room_list_models),
            )
            .route(
                "/rooms/:room_id/v1/models/:model_id",
                get(api::room_ingress::room_get_model),
            )
            .route(
                "/rooms/:room_id/v1/v1/models",
                get(api::room_ingress::room_list_models),
            )
            .route(
                "/rooms/:room_id/v1/v1/models/:model_id",
                get(api::room_ingress::room_get_model),
            )
            .layer(from_fn_with_state(state.clone(), auth::require_api_key))
    } else {
        Router::new()
    };

    let public = Router::new()
        .route("/health", get(health))
        // `/healthz` is the Kubernetes convention and what the production
        // Dockerfile's HEALTHCHECK and docker-compose probe actually hit.
        // Without it the container is reported unhealthy forever even
        // though the server is serving traffic fine.
        .route("/healthz", get(health))
        .route("/ws", get(ws::ws_handler));

    // `/v1/mock/*` impersonates the human — forgeable replies, tool calls,
    // and turn closures for anyone who can reach them. The routes exist
    // only when explicitly enabled (cargo feature `mock_endpoints` or
    // `OPENHUMAN_MOCK_ENDPOINTS=1`); otherwise probes get a plain 404.
    let mock = if api::mock::mock_enabled() {
        tracing::warn!("Mock endpoints ENABLED — /v1/mock/* can impersonate the human");
        Router::new()
            .route("/v1/mock/human-reply", post(api::mock::human_reply))
            .route("/v1/mock/tool-call", post(api::mock::tool_call))
            .route("/v1/mock/end-turn", post(api::mock::end_turn))
    } else {
        Router::new()
    };

    Router::new()
        .merge(protected)
        .merge(rooms)
        .merge(public)
        .merge(mock)
        .with_state(state)
        // Backpressure before tracing: oversized bodies are rejected with
        // 413, and excess concurrency waits rather than piling up.
        .layer(RequestBodyLimitLayer::new(max_body_bytes()))
        .layer(tower::limit::ConcurrencyLimitLayer::new(max_concurrency()))
        .layer(TraceLayer::new_for_http())
}

/// Health check endpoint.
async fn health() -> &'static str {
    "ok"
}

/// `GET /v1/models` — the single "human" model, with its limits.
///
/// Many OpenAI-compatible clients call this on startup to verify
/// connectivity, and several (DeepSeek Harness, gateway importers) also
/// auto-fill a model's context window, output cap and abilities from it.
/// There is no common schema, so the same facts are given under the names
/// clients are known to read: `context_window` / `context_length`,
/// `max_output_tokens` / `max_tokens`, their camelCase forms, and a
/// `capabilities` object. The responder is a person or an agent, so the
/// limits are generous defaults, overridable with
/// `OPENHUMAN_MODEL_CONTEXT_WINDOW` and `OPENHUMAN_MODEL_MAX_OUTPUT`.
/// The model's name is the seat's to choose (see `storage::ModelName`).
fn model_object(app: &AppState) -> serde_json::Value {
    fn env_u64(name: &str, default: u64) -> u64 {
        std::env::var(name)
            .ok()
            .and_then(|v| v.trim().parse::<u64>().ok())
            .filter(|v| *v > 0)
            .unwrap_or(default)
    }
    let context = env_u64("OPENHUMAN_MODEL_CONTEXT_WINDOW", 1_000_000);
    let output = env_u64("OPENHUMAN_MODEL_MAX_OUTPUT", 131_072);
    let name = app.model.get();
    serde_json::json!({
        "id": name,
        "object": "model",
        // Anthropic's model object.
        "type": "model",
        "display_name": name,
        "created_at": "2023-11-14T22:13:20Z",
        "created": 1700000000,
        "owned_by": "openhuman",
        "name": name,
        "context_window": context,
        "context_length": context,
        "max_output_tokens": output,
        "max_tokens": output,
        "contextWindow": context,
        "maxTokens": output,
        "input_modalities": ["text", "image"],
        "input": ["text", "image"],
        "reasoning": false,
        "capabilities": {
            "vision": true,
            "tools": true,
            "function_calling": true,
            "reasoning": false,
            "streaming": true
        }
    })
}

async fn list_models(
    axum::extract::State(app): axum::extract::State<AppState>,
) -> axum::Json<serde_json::Value> {
    let name = app.model.get();
    axum::Json(serde_json::json!({
        "object": "list",
        "data": [model_object(&app)],
        "has_more": false,
        "first_id": name,
        "last_id": name,
    }))
}

/// `GET /v1/models/:id` — every model name reaches the same responder, so
/// whatever id a client checks for exists (it is reported back as asked).
async fn get_model(
    axum::extract::State(app): axum::extract::State<AppState>,
    axum::extract::Path(model_id): axum::extract::Path<String>,
) -> axum::Json<serde_json::Value> {
    let mut m = model_object(&app);
    m["id"] = serde_json::Value::String(model_id);
    axum::Json(m)
}

/// `GET /v1/tokenizers` — the tokenizers usage can be counted with. Only
/// ones that loaded are listed; pick one with `x-openhuman-tokenizer`.
async fn list_tokenizers() -> axum::Json<serde_json::Value> {
    axum::Json(serde_json::json!({
        "default": crate::session::default_tokenizer(),
        "tokenizers": crate::session::available_tokenizers(),
    }))
}
