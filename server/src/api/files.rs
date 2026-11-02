//! `/v1/files`: the OpenAI and Anthropic Files APIs, so a caller that
//! uploads first and then refers to a `file_id` (SDKs, Anthropic's
//! `{"type": "file"}` document source) reaches the seat with the file
//! itself. Backed by the FileRepository (memory or postgres): files
//! survive restarts with the postgres backend, and byte quotas are
//! enforced by the repository on every write. Files are owned by the
//! uploading key's agent.

use axum::extract::{Multipart, Path, State};
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::state::AuthPrincipal;
use crate::storage::AppState;

#[derive(Clone)]
pub struct StoredFile {
    pub owner: String,
    pub filename: String,
    pub mime: String,
    pub purpose: String,
    pub bytes: Vec<u8>,
    pub created_at: i64,
}

/// Purpose of a file a seat made to answer an API task (a picture, audio).
/// Only these are served without a key, at their unguessable id.
pub const OUTPUT_PURPOSE: &str = "output";

// ── Sync read cache ──
//
// Files are immutable once stored, so a process-local cache can serve the
// deep synchronous conversion paths (ChatContent::to_text, image_urls,
// the Anthropic/Responses part folding) that cannot await. The repository
// stays the source of truth: every async read or write hydrates the
// cache, and request entry points prewarm it from the body (any
// `file_id` key, any shape). A stale hit after repo-side quota eviction
// returns content that did exist — semantically harmless, and bounded by
// the cache cap below.
fn cache() -> &'static std::sync::RwLock<std::collections::HashMap<String, StoredFile>> {
    static C: std::sync::OnceLock<
        std::sync::RwLock<std::collections::HashMap<String, StoredFile>>,
    > = std::sync::OnceLock::new();
    C.get_or_init(|| std::sync::RwLock::new(std::collections::HashMap::new()))
}

fn cache_insert(id: &str, f: &StoredFile) {
    let mut c = cache().write().unwrap();
    // Bounded: a full cache keeps its newest half by creation time.
    if c.len() >= 512 {
        let mut by_age: Vec<(i64, String)> =
            c.values().map(|f| (f.created_at, String::new())).collect();
        let mut pairs: Vec<(i64, String)> =
            c.iter().map(|(id, f)| (f.created_at, id.clone())).collect();
        pairs.sort();
        by_age.append(&mut pairs);
        for (_, id) in by_age.into_iter().take(256) {
            c.remove(&id);
        }
    }
    c.insert(id.to_string(), f.clone());
}

/// A file from the process-local cache, for sync conversion paths.
/// Misses mean "not hydrated here", not "does not exist".
pub fn cached(id: &str) -> Option<StoredFile> {
    cache().read().unwrap().get(id.trim()).cloned()
}

/// The cached file as a named data URL (see [`cached`]).
pub fn cached_data_url(id: &str) -> Option<String> {
    let f = cached(id)?;
    Some(crate::openai_compat::named_data_url(
        &f.mime,
        Some(&f.filename),
        &crate::openai_compat::b64_encode(&f.bytes),
    ))
}

/// Hydrate the cache for every `file_id` a request body names, in any
/// nested position, so the sync conversion core sees current files.
pub async fn prewarm(app: &AppState, body: &Value) {
    let mut ids = Vec::new();
    let mut stack = vec![body];
    while let Some(v) = stack.pop() {
        match v {
            Value::Object(o) => {
                for (k, x) in o {
                    if k == "file_id" {
                        if let Some(id) = x.as_str() {
                            if cached(id).is_none() {
                                ids.push(id.to_string());
                            }
                        }
                    } else {
                        stack.push(x);
                    }
                }
            }
            Value::Array(a) => stack.extend(a.iter()),
            _ => {}
        }
    }
    for id in ids {
        if let Some(f) = app.file.get_file(&id).await {
            cache_insert(&id, &f);
        }
    }
}

/// Store a file, minting its id (`file-<32 hex>`).
pub async fn put(app: &AppState, f: StoredFile) -> String {
    let id = format!("file-{}", Uuid::now_v7().simple());
    app.file.put_file(&id, f.clone()).await;
    cache_insert(&id, &f);
    id
}

/// A stored file as a named data URL, when it exists (any owner: ids are
/// unguessable and only reach the seat inside the owner's own request).
pub async fn data_url(app: &AppState, id: &str) -> Option<String> {
    let f = app.file.get_file(id.trim()).await?;
    Some(crate::openai_compat::named_data_url(
        &f.mime,
        Some(&f.filename),
        &crate::openai_compat::b64_encode(&f.bytes),
    ))
}

/// A stored file, whoever owns it (ids are unguessable).
/// When exactly these bytes were produced by the seat through this server:
/// (what made it, when). `purpose == output` is the trust signal: only
/// server-side `put` callers may set it (callers cannot upload with it), so
/// every output file in the store came back from the seat, whichever key —
/// the seat's or the caller's — it was stored under.
pub async fn made_by_seat(app: &AppState, bytes: &[u8]) -> Option<(String, i64)> {
    app.file
        .find_output_by_bytes(bytes)
        .await
        .map(|(_, ts)| ("openhuman-seat".to_string(), ts))
}

pub async fn get(app: &AppState, id: &str) -> Option<StoredFile> {
    let f = app.file.get_file(id.trim()).await?;
    cache_insert(id.trim(), &f);
    Some(f)
}

/// The mime type of common media from its first bytes.
pub fn sniff_mime(b: &[u8]) -> Option<&'static str> {
    let starts = |p: &[u8]| b.starts_with(p);
    if starts(b"\x89PNG\r\n\x1a\n") {
        Some("image/png")
    } else if starts(&[0xFF, 0xD8, 0xFF]) {
        Some("image/jpeg")
    } else if starts(b"GIF8") {
        Some("image/gif")
    } else if starts(b"RIFF") && b.get(8..12) == Some(b"WEBP") {
        Some("image/webp")
    } else if starts(b"RIFF") && b.get(8..12) == Some(b"WAVE") {
        Some("audio/wav")
    } else if starts(b"ID3") || (b.len() > 1 && b[0] == 0xFF && b[1] & 0xE0 == 0xE0) {
        Some("audio/mpeg")
    } else if starts(b"fLaC") {
        Some("audio/flac")
    } else if starts(b"OggS") {
        Some("audio/ogg")
    } else if b.get(4..8) == Some(b"ftyp") {
        Some("video/mp4")
    } else if starts(&[0x1A, 0x45, 0xDF, 0xA3]) {
        Some("video/webm")
    } else if starts(b"%PDF") {
        Some("application/pdf")
    } else {
        None
    }
}

/// `GET /files/:id`: a seat-made output, without a key, so a URL in an
/// API answer (`response_format: "url"`) opens in any browser or SDK.
pub async fn public(State(app): State<AppState>, Path(id): Path<String>) -> Response {
    let id = id.split('.').next().unwrap_or("").to_string();
    match get(&app, &id).await.filter(|f| f.purpose == OUTPUT_PURPOSE) {
        Some(f) => (
            [
                (header::CONTENT_TYPE, f.mime.clone()),
                (header::CACHE_CONTROL, "private, max-age=3600".to_string()),
            ],
            f.bytes,
        )
            .into_response(),
        None => not_found(&id),
    }
}

pub fn meta(id: &str, f: &StoredFile) -> Value {
    // One object both SDK families accept: OpenAI's FileObject fields and
    // Anthropic's FileMetadata fields side by side.
    let created = chrono::DateTime::from_timestamp(f.created_at, 0)
        .map(|d| d.to_rfc3339())
        .unwrap_or_default();
    json!({
        "id": id,
        "object": "file",
        "type": "file",
        "bytes": f.bytes.len(),
        "size_bytes": f.bytes.len(),
        "created_at": f.created_at,
        "created_at_iso": created,
        "filename": f.filename,
        "mime_type": f.mime,
        "purpose": f.purpose,
        "status": "processed",
        "downloadable": true,
    })
}

fn not_found(id: &str) -> Response {
    (
        StatusCode::NOT_FOUND,
        Json(json!({"error": {"message": format!("No such file: {id}"), "type": "invalid_request_error", "code": "file_not_found"}})),
    )
        .into_response()
}

pub async fn upload(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    mut mp: Multipart,
) -> Response {
    let mut file: Option<(String, String, Vec<u8>)> = None;
    let mut purpose = "user_data".to_string();
    loop {
        let field = match mp.next_field().await {
            Ok(Some(f)) => f,
            Ok(None) => break,
            Err(e) => return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": {"message": e.to_string(), "type": "invalid_request_error"}})),
            )
                .into_response(),
        };
        let name = field.name().unwrap_or("").to_string();
        if name == "purpose" {
            purpose = field.text().await.unwrap_or_default();
            continue;
        }
        if name != "file" {
            continue;
        }
        let filename = field.file_name().unwrap_or("upload").to_string();
        let mime = field
            .content_type()
            .map(|s| s.to_string())
            .filter(|m| !m.is_empty() && m != "application/octet-stream")
            .unwrap_or_else(|| crate::openai_compat::guess_mime(&filename).to_string());
        match field.bytes().await {
            Ok(b) => file = Some((filename, mime, b.to_vec())),
            Err(e) => return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": {"message": e.to_string(), "type": "invalid_request_error"}})),
            )
                .into_response(),
        }
    }
    // `output` marks seat-made files served on the anonymous download route;
    // letting a caller set it would hand out public URLs for arbitrary
    // uploaded content. Only server-side `put` callers may use it.
    if purpose == OUTPUT_PURPOSE {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": {"message": format!("purpose \"{OUTPUT_PURPOSE}\" is reserved for files the seat produces"), "type": "invalid_request_error"}})),
        )
            .into_response();
    }
    let Some((filename, mime, bytes)) = file else {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": {"message": "multipart field `file` is required", "type": "invalid_request_error"}})),
        )
            .into_response();
    };
    let f = StoredFile {
        owner: principal.agent.id.clone(),
        filename,
        mime,
        purpose,
        bytes,
        created_at: chrono::Utc::now().timestamp(),
    };
    let id = put(&app, f.clone()).await;
    Json(meta(&id, &f)).into_response()
}

async fn owned(app: &AppState, principal: &AuthPrincipal, id: &str) -> Option<StoredFile> {
    app.file
        .get_file(id)
        .await
        .filter(|f| f.owner == principal.agent.id)
}

pub async fn get_meta(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    match owned(&app, &principal, &id).await {
        Some(f) => Json(meta(&id, &f)).into_response(),
        None => not_found(&id),
    }
}

pub async fn content(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    match owned(&app, &principal, &id).await {
        Some(f) => ([(header::CONTENT_TYPE, f.mime.clone())], f.bytes).into_response(),
        None => not_found(&id),
    }
}

pub async fn list(State(app): State<AppState>, principal: AuthPrincipal) -> Response {
    let data: Vec<Value> = app
        .file
        .list_files(&principal.agent.id)
        .await
        .iter()
        .map(|(id, f)| meta(id, f))
        .collect();
    Json(json!({"object": "list", "data": data, "has_more": false})).into_response()
}

pub async fn delete(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    if !app.file.delete_file(&principal.agent.id, &id).await {
        return not_found(&id);
    }
    Json(json!({"id": id, "object": "file", "type": "file_deleted", "deleted": true}))
        .into_response()
}
