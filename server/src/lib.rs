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
pub mod seat;
pub mod state;
pub mod storage;
pub mod ws;

use axum::middleware::from_fn_with_state;
use axum::routing::{delete, get, patch, post};
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
        .route("/v1/models", get(list_models))
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
        .route(
            "/v1/conversations/:conversation_id/restore",
            post(api::history::restore_conversation),
        )
        .route(
            "/v1/conversations/:conversation_id/permanent",
            delete(api::history::delete_conversation_permanent),
        )
        // The seeded agent name is rarely what the human calls it.
        .route("/v1/agents/:agent_id", patch(api::history::rename_agent))
        // Agent Seat: the human seat over plain HTTP, for agents that
        // cannot hold a WebSocket (see `seat.rs`).
        .route("/v1/seat/inbox", get(seat::inbox))
        .route("/v1/seat/send", post(seat::send))
        .route("/v1/seat/reply", post(seat::reply))
        .route("/v1/seat/tool-call", post(seat::tool_call))
        .route("/v1/seat/capabilities", get(seat::capabilities))
        // Observation runs *inside* auth: only authenticated requests are
        // captured, so an anonymous caller cannot fill the disk.
        .layer(axum::middleware::from_fn(observation::observe_request))
        .layer(from_fn_with_state(state.clone(), auth::require_api_key));

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

/// `GET /v1/models` — returns a minimal model list.
///
/// Many OpenAI-compatible clients call this on startup to verify
/// connectivity. We return a single "human" model.
async fn list_models() -> axum::Json<serde_json::Value> {
    axum::Json(serde_json::json!({
        "object": "list",
        "data": [{
            "id": "openhuman-human",
            "object": "model",
            "created": 1700000000,
            "owned_by": "openhuman"
        }]
    }))
}
