//! Caller keys for people: the seat hands each friend a key of their own.
//!
//! Sharing the seat's own key meant everyone who could message you could
//! also answer as you, and nobody could be cut off without cutting off
//! everyone. A caller key can only ask; it carries the name of the person
//! it was made for, so their messages arrive under that name; and it is
//! revoked on its own.
//!
//! - `POST   /v1/seat/caller-keys`      `{ "name": "林晓" }` → the key, once
//! - `GET    /v1/seat/caller-keys`      who holds a key, and whether it works
//! - `DELETE /v1/seat/caller-keys/:id`  revoke one

use std::collections::HashMap;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Json, Response};
use chrono::Utc;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::auth::AuthPrincipal;
use crate::model::identity::{AgentIdentity, ApiKey, ClientType, KeyScope};
use crate::storage::AppState;

/// Longest name a caller key may carry, in characters.
const MAX_NAME: usize = 48;

fn err(status: StatusCode, code: &str, message: &str) -> Response {
    (
        status,
        Json(json!({ "error": { "code": code, "message": message, "type": "invalid_request_error" } })),
    )
        .into_response()
}

fn seat_only(principal: &AuthPrincipal) -> Option<Response> {
    if principal.api_key.scope.may_respond() && principal.api_key.room_id.is_none() {
        None
    } else {
        Some(err(
            StatusCode::FORBIDDEN,
            "forbidden",
            "Only the seat may hand out or revoke caller keys.",
        ))
    }
}

#[derive(Debug, Deserialize)]
pub struct CreateBody {
    name: String,
}

/// Mint a caller key for one person. The raw key is in this response
/// only; the server keeps its hash.
pub async fn create(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Json(b): Json<CreateBody>,
) -> Response {
    if let Some(r) = seat_only(&principal) {
        return r;
    }
    let name = b.name.trim();
    if name.is_empty() || name.chars().count() > MAX_NAME || name.chars().any(char::is_control) {
        return err(
            StatusCode::BAD_REQUEST,
            "invalid_name",
            "A name is 1–48 characters with no control characters.",
        );
    }

    let key_id = format!("key_{}", Uuid::now_v7().simple());
    let raw_key = format!("ohk_{}", hex::encode(Uuid::new_v4().into_bytes()));
    let agent_id = format!("agt_{}", Uuid::now_v7().simple());
    app.identity
        .insert_agent(AgentIdentity {
            id: agent_id.clone(),
            name: name.to_string(),
            client_type: ClientType::Custom,
            api_key_id: key_id.clone(),
            capabilities: Vec::new(),
            metadata: HashMap::new(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        })
        .await;
    app.identity
        .insert_api_key(
            ApiKey::new(
                key_id.clone(),
                &raw_key,
                agent_id.clone(),
                principal.human.id.clone(),
            )
            .with_scope(KeyScope::Caller),
        )
        .await;

    (
        StatusCode::CREATED,
        Json(json!({
            "id": key_id,
            "agent_id": agent_id,
            "name": name,
            "api_key": raw_key,
            "model": app.model.get(),
            "note": "Shown once; only its hash is stored. It can ask, never answer.",
        })),
    )
        .into_response()
}

/// Who holds a caller key from this seat, oldest first.
pub async fn list(State(app): State<AppState>, principal: AuthPrincipal) -> Response {
    if let Some(r) = seat_only(&principal) {
        return r;
    }
    let keys = app.identity.list_caller_keys(&principal.human.id).await;
    let data: Vec<_> = keys
        .into_iter()
        .map(|k| {
            json!({
                "id": k.id,
                "agent_id": k.agent_id,
                "name": k.name,
                "revoked": k.scope == KeyScope::Revoked,
            })
        })
        .collect();
    Json(json!({ "object": "list", "data": data })).into_response()
}

/// Revoke one caller key. Its holder can no longer ask; their past
/// conversations stay.
pub async fn revoke(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(key_id): Path<String>,
) -> Response {
    if let Some(r) = seat_only(&principal) {
        return r;
    }
    // Never the key in use: revoking yourself here would lock the seat out.
    if key_id == principal.api_key.id {
        return err(
            StatusCode::BAD_REQUEST,
            "cannot_revoke_self",
            "This is the key you are signed in with.",
        );
    }
    let owned = app
        .identity
        .list_caller_keys(&principal.human.id)
        .await
        .into_iter()
        .any(|k| k.id == key_id);
    if !owned || !app.identity.revoke_key(&principal.human.id, &key_id).await {
        return err(StatusCode::NOT_FOUND, "not_found", "No such caller key.");
    }
    Json(json!({ "id": key_id, "revoked": true })).into_response()
}
