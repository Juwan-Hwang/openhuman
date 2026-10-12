//! Conversation history — `GET /v1/conversations` and its messages.
//!
//! The backlog pushed when a console connects carries only messages that
//! have not reached a device yet. That is deliberate: replaying everything
//! made the human watch conversations they had already answered arrive
//! again, and on a long thread the burst was large enough to swamp the
//! connection.
//!
//! It does mean a freshly opened console starts empty unless it asks for
//! the past, which is what these endpoints are for.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Json};
use serde::Deserialize;
use serde_json::json;

use crate::state::AuthPrincipal;
use crate::storage::AppState;

/// Query parameters for the message listing.
#[derive(Debug, Deserialize)]
pub struct MessagesQuery {
    /// How many of the most recent messages to return.
    #[serde(default = "default_limit")]
    pub limit: usize,
}

fn default_limit() -> usize {
    100
}

/// Upper bound on `?limit=`, so one request cannot ask for the whole table.
const MAX_LIMIT: usize = 500;

/// Query parameters for the conversation listing.
#[derive(Debug, Deserialize)]
pub struct ConversationsQuery {
    /// How many of the most recently active conversations to return.
    #[serde(default = "default_conversation_limit")]
    pub limit: usize,

    /// Return the trash instead of the live conversations.
    #[serde(default)]
    pub deleted: bool,
}

/// Body accepted when renaming an agent.
#[derive(Debug, Deserialize)]
pub struct RenameAgentRequest {
    pub name: String,
}

fn default_conversation_limit() -> usize {
    50
}

/// List the authenticated human's conversations, newest activity first.
pub async fn list_conversations(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Query(query): Query<ConversationsQuery>,
) -> impl IntoResponse {
    let human_id = principal.human.id.clone();
    let limit = query.limit.clamp(1, MAX_LIMIT);

    let mut conversations = if query.deleted {
        app.conversation.list_deleted_for_human(&human_id).await
    } else {
        app.conversation.list_for_human(&human_id).await
    };

    // Newest activity first, so a capped listing returns the ones that
    // matter. Without sorting, truncating would keep an arbitrary slice.
    conversations.sort_by_key(|c| std::cmp::Reverse(c.last_message_at.unwrap_or(c.created_at)));
    let total = conversations.len();
    conversations.truncate(limit);

    // Resolved once per distinct agent, not once per conversation. There
    // are only ever a handful of agents, but a lot of conversations —
    // querying inside the loop made this endpoint take seconds.
    let mut names: std::collections::HashMap<String, Option<String>> =
        std::collections::HashMap::new();

    let out: Vec<serde_json::Value> = {
        let mut rows = Vec::with_capacity(conversations.len());
        for c in &conversations {
            // The display name is what a console actually shows; the raw
            // agent id is for correlation, not for humans.
            let agent_name = match c.agent_id() {
                Some(id) => match names.get(id) {
                    Some(cached) => cached.clone(),
                    None => {
                        let name = app.identity.get_agent(id).await.map(|a| a.name);
                        names.insert(id.to_string(), name.clone());
                        name
                    }
                },
                None => None,
            };

            rows.push(json!({
                "id": c.id,
                "agent_id": c.agent_id(),
                "agent_name": agent_name,
                "human_id": c.human_id(),
                "last_message_at": c.last_message_at.map(|t| t.to_rfc3339()),
                "created_at": c.created_at.to_rfc3339(),
            }));
        }
        rows
    };

    (StatusCode::OK, Json(json!({ "data": out, "total": total }))).into_response()
}

/// List a conversation's messages, oldest first.
///
/// Images are included, so a console can render what the agent sent rather
/// than just the text the server kept alongside it.
///
/// Scoped to the caller's own conversations like every other endpoint here:
/// conversation ids are guessable, and without the ownership check any key
/// could read any transcript.
pub async fn list_messages(
    State(app): State<AppState>,
    Path(conversation_id): Path<String>,
    principal: axum::Extension<AuthPrincipal>,
    Query(query): Query<MessagesQuery>,
) -> impl IntoResponse {
    if !owns_conversation(&app, &conversation_id, &principal.human.id).await {
        return not_found();
    }

    let limit = query.limit.clamp(1, MAX_LIMIT);
    let mut messages = app.message.list(&conversation_id).await;

    // Newest last is what a chat timeline wants; take the tail so a caller
    // asking for 100 gets the 100 most recent, not the oldest 100.
    let start = messages.len().saturating_sub(limit);
    messages = messages.split_off(start);

    let out: Vec<serde_json::Value> = messages
        .iter()
        .map(|m| {
            let images: Vec<String> = m
                .metadata
                .get("images")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();

            json!({
                "id": m.id,
                "conversation_id": m.conversation_id,
                "sender_id": m.sender.participant_id,
                "sender_type": format!("{:?}", m.sender.participant_type).to_lowercase(),
                "sender_name": m.sender.display_name,
                "text": m.content.as_text().unwrap_or(""),
                "images": images,
                "created_at": m.created_at.to_rfc3339(),
            })
        })
        .collect();

    (StatusCode::OK, Json(json!({ "data": out }))).into_response()
}

/// Rename an agent the caller is paired with.
///
/// `PATCH /v1/agents/:agent_id`
///
/// The seeded name is whatever the demo data or the issuing tool chose,
/// which is rarely what the human calls it. Scoped to the caller's own
/// agents so one key cannot rename another's.
pub async fn rename_agent(
    State(app): State<AppState>,
    Path(agent_id): Path<String>,
    principal: axum::Extension<AuthPrincipal>,
    Json(body): Json<RenameAgentRequest>,
) -> impl IntoResponse {
    let name = body.name.trim();

    if name.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "error": { "message": "A name is required.", "type": "invalid_request_error" }
            })),
        )
            .into_response();
    }

    // Long enough to be a name, short enough not to wreck the sidebar.
    if name.chars().count() > 64 {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "error": { "message": "Name must be 64 characters or fewer.", "type": "invalid_request_error" }
            })),
        )
            .into_response();
    }

    match app
        .identity
        .rename_agent(&agent_id, &principal.human.id, &principal.api_key.id, name)
        .await
    {
        Some(agent) => (
            StatusCode::OK,
            Json(json!({ "data": { "id": agent.id, "name": agent.name } })),
        )
            .into_response(),
        None => (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": { "message": "No such agent for this key.", "type": "not_found" }
            })),
        )
            .into_response(),
    }
}

/// Move a conversation to the trash.
///
/// `DELETE /v1/conversations/:conversation_id`
///
/// Restorable via [restore_conversation]. Deleting outright would take
/// every message with it and leave no way back.
pub async fn delete_conversation(
    State(app): State<AppState>,
    Path(conversation_id): Path<String>,
    principal: axum::Extension<AuthPrincipal>,
) -> impl IntoResponse {
    if !owns_conversation(&app, &conversation_id, &principal.human.id).await {
        return not_found();
    }

    if app.conversation.soft_delete(&conversation_id).await {
        (
            StatusCode::OK,
            Json(json!({ "data": { "id": conversation_id, "deleted": true } })),
        )
            .into_response()
    } else {
        not_found()
    }
}

/// Take a conversation back out of the trash.
///
/// `POST /v1/conversations/:conversation_id/restore`
pub async fn restore_conversation(
    State(app): State<AppState>,
    Path(conversation_id): Path<String>,
    principal: axum::Extension<AuthPrincipal>,
) -> impl IntoResponse {
    if !owns_conversation(&app, &conversation_id, &principal.human.id).await {
        return not_found();
    }

    if app.conversation.restore(&conversation_id).await {
        (
            StatusCode::OK,
            Json(json!({ "data": { "id": conversation_id, "deleted": false } })),
        )
            .into_response()
    } else {
        not_found()
    }
}

/// Destroy a conversation for good.
///
/// `DELETE /v1/conversations/:conversation_id/permanent`
pub async fn delete_conversation_permanent(
    State(app): State<AppState>,
    Path(conversation_id): Path<String>,
    principal: axum::Extension<AuthPrincipal>,
) -> impl IntoResponse {
    if !owns_conversation(&app, &conversation_id, &principal.human.id).await {
        return not_found();
    }

    if app.conversation.delete_permanent(&conversation_id).await {
        (
            StatusCode::OK,
            Json(json!({ "data": { "id": conversation_id, "destroyed": true } })),
        )
            .into_response()
    } else {
        not_found()
    }
}

/// Whether this human is a participant of the conversation.
///
/// Every conversation endpoint checks this: ids are guessable, and acting
/// on one that is not yours is either a 404 or a data leak depending on
/// how careless the handler is.
async fn owns_conversation(app: &AppState, conversation_id: &str, human_id: &str) -> bool {
    let owned = app
        .conversation
        .list_for_human(human_id)
        .await
        .iter()
        .any(|c| c.id == conversation_id);

    if owned {
        return true;
    }

    // Trashed conversations are not in the live list but still belong to
    // their human — restoring and destroying have to reach them.
    app.conversation
        .list_deleted_for_human(human_id)
        .await
        .iter()
        .any(|c| c.id == conversation_id)
}

fn not_found() -> axum::response::Response {
    (
        StatusCode::NOT_FOUND,
        Json(json!({
            "error": { "message": "No such conversation.", "type": "not_found" }
        })),
    )
        .into_response()
}
