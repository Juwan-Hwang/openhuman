//! Room management API (design doc §5.1) — the responder side of group
//! rooms: create, list, settings, invites, membership, catch-up reads,
//! and room-bound caller keys. The caller ingress (`/rooms/:id/v1/*`)
//! lives in `openai.rs`; this module is human-side only.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use chrono::{Duration, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::model::conversation::ParticipantRole;
use crate::model::identity::{AgentIdentity, ApiKey, ClientType, KeyScope, ParticipantRef};
use crate::state::AuthPrincipal;
use crate::storage::traits::RoomInvite;
use crate::storage::AppState;
use crate::ws::protocol;

fn err(status: StatusCode, code: &str, message: &str) -> (StatusCode, Json<Value>) {
    (
        status,
        Json(json!({"error": {"message": message, "type": "invalid_request_error", "code": code}})),
    )
}

/// The acting human's id, from the responder principal.
fn actor(principal: &AuthPrincipal) -> String {
    principal.human.id.clone()
}

async fn require_room(
    app: &AppState,
    room_id: &str,
) -> Result<crate::model::conversation::Conversation, (StatusCode, Json<Value>)> {
    match app.conversation.get(room_id).await {
        Some(c) if c.conversation_type == crate::model::conversation::ConversationType::Group => {
            Ok(c)
        }
        _ => Err(err(
            StatusCode::NOT_FOUND,
            "room_not_found",
            "No such room.",
        )),
    }
}

async fn require_owner(
    app: &AppState,
    room_id: &str,
    human_id: &str,
) -> Result<(), (StatusCode, Json<Value>)> {
    match app.room.room_member_role(room_id, human_id).await {
        Some(ParticipantRole::Owner) => Ok(()),
        _ => Err(err(
            StatusCode::FORBIDDEN,
            "owner_only",
            "Only the room owner can do this.",
        )),
    }
}

// ── Create / list / detail / settings ──

#[derive(Deserialize)]
pub struct CreateRoom {
    name: String,
}

pub async fn create_room(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Json(body): Json<CreateRoom>,
) -> Result<(StatusCode, Json<Value>), (StatusCode, Json<Value>)> {
    let name = body.name.trim();
    if name.is_empty() || name.chars().count() > 64 {
        return Err(err(
            StatusCode::BAD_REQUEST,
            "bad_name",
            "Room name must be 1-64 characters.",
        ));
    }
    let owner_id = actor(&principal);
    let owner_name = principal.human.display_name.clone();
    let room_id = format!("room_{}", Uuid::now_v7().simple());
    let room = app
        .room
        .room_create(
            &room_id,
            name,
            &ParticipantRef::human_named(&owner_id, &owner_name),
        )
        .await;
    Ok((StatusCode::CREATED, Json(room_json(&room))))
}

fn room_json(room: &crate::model::conversation::Conversation) -> Value {
    json!({
        "id": room.id,
        "type": "group",
        "name": room.title,
        "model": room.title, // the room's name is its public model name
        "member_count": room.participants.len(),
        "metadata": room.metadata,
        "created_at": room.created_at,
    })
}

pub async fn list_rooms(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
) -> Json<Value> {
    let human_id = actor(&principal);
    let rooms: Vec<Value> = app
        .conversation
        .list_for_human(&human_id)
        .await
        .iter()
        .filter(|c| c.conversation_type == crate::model::conversation::ConversationType::Group)
        .map(room_json)
        .collect();
    Json(json!({"rooms": rooms}))
}

pub async fn get_room(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Path(room_id): Path<String>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let room = require_room(&app, &room_id).await?;
    let human_id = actor(&principal);
    if app
        .room
        .room_member_role(&room_id, &human_id)
        .await
        .is_none()
    {
        return Err(err(
            StatusCode::FORBIDDEN,
            "not_a_member",
            "You are not a member of this room.",
        ));
    }
    let mut members = Vec::new();
    for p in &room.participants {
        let name = app
            .identity
            .get_human(&p.participant.participant_id)
            .await
            .map(|h| h.display_name)
            .unwrap_or_else(|| p.participant.participant_id.clone());
        members.push(json!({
            "participant_id": p.participant.participant_id,
            "display_name": name,
            "role": p.role.map(|r| match r {
                ParticipantRole::Owner => "owner",
                ParticipantRole::Member => "member",
                ParticipantRole::Initiator => "initiator",
                ParticipantRole::Responder => "responder",
                ParticipantRole::Observer => "observer",
            }),
            "joined_at": p.joined_at,
            "first_visible_seq": p.first_visible_seq,
        }));
    }
    let mut v = room_json(&room);
    v["members"] = Value::Array(members);
    Ok(Json(v))
}

#[derive(Deserialize)]
pub struct PatchRoom {
    room_idle_secs: Option<u64>,
    room_segmented: Option<bool>,
    room_segment_quiet_secs: Option<u64>,
    room_segment_max_secs: Option<u64>,
    room_deep_idle_mins: Option<u64>,
}

pub async fn patch_room(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Path(room_id): Path<String>,
    Json(body): Json<PatchRoom>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    require_room(&app, &room_id).await?;
    require_owner(&app, &room_id, &actor(&principal)).await?;
    let mut patch = serde_json::Map::new();
    if let Some(v) = body.room_idle_secs {
        patch.insert("room_idle_secs".into(), json!(v));
    }
    if let Some(v) = body.room_segmented {
        patch.insert("room_segmented".into(), json!(v));
    }
    if let Some(v) = body.room_segment_quiet_secs {
        patch.insert("room_segment_quiet_secs".into(), json!(v));
    }
    if let Some(v) = body.room_segment_max_secs {
        patch.insert("room_segment_max_secs".into(), json!(v));
    }
    if let Some(v) = body.room_deep_idle_mins {
        patch.insert("room_deep_idle_mins".into(), json!(v));
    }
    app.room
        .room_update_metadata(&room_id, Value::Object(patch))
        .await;
    let room = require_room(&app, &room_id).await?;
    Ok(Json(room_json(&room)))
}

// ── Invites ──

/// Rate limit for invite acceptance: per account and per IP.
/// 10 accepts per 10 minutes each — generous for real use, tight for
/// grinding 128-bit codes.
struct AcceptLimiter {
    hits: Mutex<HashMap<String, Vec<Instant>>>,
}

impl AcceptLimiter {
    fn new() -> Self {
        Self {
            hits: Mutex::new(HashMap::new()),
        }
    }
    fn allow(&self, key: &str) -> bool {
        let mut map = self.hits.lock().unwrap();
        let now = Instant::now();
        let window = std::time::Duration::from_secs(600);
        let hits = map.entry(key.to_string()).or_default();
        hits.retain(|t| now.duration_since(*t) < window);
        if hits.len() >= 10 {
            return false;
        }
        hits.push(now);
        true
    }
}

fn limiter() -> Arc<AcceptLimiter> {
    static ONCE: std::sync::OnceLock<Arc<AcceptLimiter>> = std::sync::OnceLock::new();
    ONCE.get_or_init(|| Arc::new(AcceptLimiter::new())).clone()
}

/// A fresh invite code: 128 bits of randomness, hex-encoded. Only the
/// SHA-256 digest is stored; the plaintext appears exactly once, here.
fn mint_code() -> String {
    hex::encode(Uuid::new_v4().into_bytes())
}

pub async fn create_invite(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Path(room_id): Path<String>,
) -> Result<(StatusCode, Json<Value>), (StatusCode, Json<Value>)> {
    require_room(&app, &room_id).await?;
    let owner_id = actor(&principal);
    require_owner(&app, &room_id, &owner_id).await?;
    let code = mint_code();
    let invite = RoomInvite {
        code_hash: crate::crypto::sha256_hex(&code),
        room_id: room_id.clone(),
        created_by: owner_id,
        created_at: Utc::now(),
        expires_at: Utc::now() + Duration::hours(24),
        revoked_at: None,
    };
    let expires = invite.expires_at;
    if !app.room.room_invite_create(invite).await {
        return Err(err(
            StatusCode::INTERNAL_SERVER_ERROR,
            "invite_failed",
            "Could not create invite.",
        ));
    }
    Ok((
        StatusCode::CREATED,
        Json(json!({
            "code": code,
            "room_id": room_id,
            "expires_at": expires,
            "note": "Shown once. Reusable until it expires or is revoked.",
        })),
    ))
}

pub async fn revoke_invite(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Path((room_id, code)): Path<(String, String)>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    require_room(&app, &room_id).await?;
    require_owner(&app, &room_id, &actor(&principal)).await?;
    let hash = crate::crypto::sha256_hex(&code);
    if app.room.room_invite_revoke(&room_id, &hash).await {
        Ok(Json(json!({"revoked": true})))
    } else {
        Err(err(
            StatusCode::NOT_FOUND,
            "invite_not_found",
            "No live invite with that code for this room.",
        ))
    }
}

pub async fn accept_invite(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    headers: HeaderMap,
    Path(code): Path<String>,
) -> Result<(StatusCode, Json<Value>), (StatusCode, Json<Value>)> {
    let human_id = actor(&principal);
    let ip = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "unknown".to_string());
    let lim = limiter();
    if !lim.allow(&format!("acct:{}", human_id)) || !lim.allow(&format!("ip:{}", ip)) {
        return Err(err(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many invite attempts. Try again later.",
        ));
    }

    let hash = crate::crypto::sha256_hex(&code);
    let Some(invite) = app.room.room_invite_get(&hash).await else {
        return Err(err(
            StatusCode::NOT_FOUND,
            "invite_not_found",
            "Unknown invite code.",
        ));
    };
    if invite.revoked_at.is_some() {
        return Err(err(
            StatusCode::GONE,
            "invite_revoked",
            "This invite was revoked.",
        ));
    }
    if invite.expires_at < Utc::now() {
        return Err(err(
            StatusCode::GONE,
            "invite_expired",
            "This invite expired.",
        ));
    }
    let room = require_room(&app, &invite.room_id).await?;

    // Rejoining is idempotent — you keep your original watermark.
    if app
        .room
        .room_member_role(&invite.room_id, &human_id)
        .await
        .is_some()
    {
        return Ok((StatusCode::OK, Json(room_json(&room))));
    }
    if app.room.room_member_count(&invite.room_id).await >= crate::rooms::ROOM_MAX_MEMBERS {
        return Err(err(
            StatusCode::CONFLICT,
            "room_full",
            "This room is full (10 members).",
        ));
    }

    // New members see only what comes after their join.
    let watermark = app.room.room_next_seq(&invite.room_id).await;
    let name = principal.human.display_name.clone();
    app.room
        .room_add_member(
            &invite.room_id,
            &ParticipantRef::human_named(&human_id, &name),
            ParticipantRole::Member,
            Some(watermark),
        )
        .await;
    let event = protocol::room_member_joined(&invite.room_id, &human_id, &name);
    crate::rooms::broadcast_event(&app, &invite.room_id, &event).await;
    let room = require_room(&app, &invite.room_id).await?;
    Ok((StatusCode::CREATED, Json(room_json(&room))))
}

// ── Membership ──

pub async fn leave_room(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Path(room_id): Path<String>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    require_room(&app, &room_id).await?;
    let human_id = actor(&principal);
    let role = app.room.room_member_role(&room_id, &human_id).await;
    match role {
        Some(ParticipantRole::Owner) => {
            // Owner leaving tears down the room's caller keys too.
            app.room.room_revoke_keys(&room_id).await;
            // Owners cannot be removed by the member path; delete the room.
            app.conversation.delete_permanent(&room_id).await;
        }
        Some(_) => {
            app.room.room_remove_member(&room_id, &human_id).await;
        }
        None => {
            return Err(err(
                StatusCode::FORBIDDEN,
                "not_a_member",
                "You are not a member of this room.",
            ))
        }
    }
    let name = principal.human.display_name.clone();
    let event = protocol::room_member_left(&room_id, &human_id, &name, "left");
    crate::rooms::broadcast_event(&app, &room_id, &event).await;
    Ok(Json(json!({"left": true})))
}

pub async fn kick_member(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Path((room_id, pid)): Path<(String, String)>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    require_room(&app, &room_id).await?;
    require_owner(&app, &room_id, &actor(&principal)).await?;
    if let Some(ParticipantRole::Owner) = app.room.room_member_role(&room_id, &pid).await {
        return Err(err(
            StatusCode::CONFLICT,
            "owner_cannot_be_kicked",
            "The owner cannot be kicked.",
        ));
    }
    if !app.room.room_remove_member(&room_id, &pid).await {
        return Err(err(
            StatusCode::NOT_FOUND,
            "not_a_member",
            "That participant is not in this room.",
        ));
    }
    // Fanout resolves membership fresh per send, so the kick is effective
    // for the very next room event; after_seq reads return 403 from here on.
    let name = app
        .identity
        .get_human(&pid)
        .await
        .map(|h| h.display_name)
        .unwrap_or_else(|| pid.clone());
    let event = protocol::room_member_left(&room_id, &pid, &name, "kicked");
    crate::rooms::broadcast_event(&app, &room_id, &event).await;
    Ok(Json(json!({"kicked": pid})))
}

// ── Catch-up reads ──

#[derive(Deserialize)]
pub struct AfterSeq {
    after_seq: Option<i64>,
    limit: Option<usize>,
}

pub async fn room_messages(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Path(room_id): Path<String>,
    Query(q): Query<AfterSeq>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    require_room(&app, &room_id).await?;
    let human_id = actor(&principal);
    if app
        .room
        .room_member_role(&room_id, &human_id)
        .await
        .is_none()
    {
        // Kicked members land here too: no membership, no log.
        return Err(err(
            StatusCode::FORBIDDEN,
            "not_a_member",
            "You are not a member of this room.",
        ));
    }
    let min_seq = app
        .room
        .room_first_visible_seq(&room_id, &human_id)
        .await
        .unwrap_or(0);
    let msgs = app
        .room
        .room_messages_since(
            &room_id,
            q.after_seq.unwrap_or(0),
            min_seq,
            q.limit.unwrap_or(500).min(1000),
        )
        .await;
    let out: Vec<Value> = msgs
        .iter()
        .map(|m| {
            json!({
                "id": m.id,
                "room_seq": m.room_seq,
                "sender_id": m.sender.participant_id,
                "sender_name": crate::rooms::tagged_display_name(m.sender.display_name.as_deref(), &m.metadata),
                "text": m.content.as_text().unwrap_or(""),
                "metadata": m.metadata,
                "created_at": m.created_at,
            })
        })
        .collect();
    Ok(Json(json!({"messages": out})))
}

// ── Room-bound caller keys ──

#[derive(Deserialize)]
pub struct CreateCallerKey {
    /// Required display name, e.g. "小明的 Claude Code" — used as the
    /// stream prefix and in the UI.
    display_name: String,
}

pub async fn create_caller_key(
    State(app): State<AppState>,
    principal: axum::Extension<AuthPrincipal>,
    Path(room_id): Path<String>,
    Json(body): Json<CreateCallerKey>,
) -> Result<(StatusCode, Json<Value>), (StatusCode, Json<Value>)> {
    let room = require_room(&app, &room_id).await?;
    let owner_id = actor(&principal);
    require_owner(&app, &room_id, &owner_id).await?;
    let display = body.display_name.trim();
    if display.is_empty() {
        return Err(err(
            StatusCode::BAD_REQUEST,
            "display_name_required",
            "A display name is required for a room caller key.",
        ));
    }

    let key_id = format!("key_{}", Uuid::now_v7().simple());
    let raw_key = format!("ohk_{}", hex::encode(Uuid::new_v4().into_bytes()));
    let agent_id = format!("agt_{}", Uuid::now_v7().simple());

    let agent = AgentIdentity {
        id: agent_id.clone(),
        name: display.to_string(),
        client_type: ClientType::Custom,
        api_key_id: key_id.clone(),
        capabilities: Vec::new(),
        metadata: HashMap::new(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };
    app.identity.insert_agent(agent).await;

    let mut key = ApiKey::new(key_id, &raw_key, agent_id, owner_id).with_scope(KeyScope::Caller);
    key.room_id = Some(room_id.clone());
    app.identity.insert_api_key(key).await;

    let model = room.title.clone().unwrap_or_else(|| room_id.clone());
    Ok((
        StatusCode::CREATED,
        Json(json!({
            "api_key": raw_key,
            "base_url_path": format!("/rooms/{}/v1", room_id),
            "model": model,
            "display_name": display,
            "note": "The key is shown once; only its hash is stored. It works ONLY on this room's ingress.",
        })),
    ))
}
