//! `/v1/vector_stores`: stores of files the seat searches. Files are kept
//! as they were uploaded (no embeddings of our own); a search is a seat
//! task with the store's files attached and the query as the message, and
//! the seat answers with ranked passages, checked at reply time.
//!
//! Stores and file batches persist through the ObjectRepository
//! (migration 010), not process statics.

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::{json, Value};

use crate::api::task::{self, Delivery, Finished};
use crate::auth::AuthPrincipal;
use crate::storage::traits::StoredObject;
use crate::storage::AppState;

fn err(status: StatusCode, msg: &str) -> Response {
    (
        status,
        Json(json!({"error": {"message": msg, "type": "invalid_request_error", "code": null, "param": null}})),
    )
        .into_response()
}

fn not_found(kind: &str, id: &str) -> Response {
    err(
        StatusCode::NOT_FOUND,
        &format!("No {kind} found with id '{id}'."),
    )
}

fn now() -> i64 {
    chrono::Utc::now().timestamp()
}

async fn get_store(app: &AppState, owner: &str, id: &str) -> Option<StoredObject> {
    app.object
        .get_object(owner, id)
        .await
        .filter(|s| s.obj["object"] == "vector_store")
}

/// Recount the store's files and bytes after a change.
async fn refresh(app: &AppState, owner: &str, id: &str) {
    let Some(mut s) = app.object.get_object(owner, id).await else {
        return;
    };
    let total = s.input.len();
    let bytes: u64 = s
        .input
        .iter()
        .filter_map(|f| f["usage_bytes"].as_u64())
        .sum();
    s.obj["file_counts"] =
        json!({"in_progress": 0, "completed": total, "failed": 0, "cancelled": 0, "total": total});
    s.obj["usage_bytes"] = json!(bytes);
    s.obj["last_active_at"] = json!(now());
    app.object
        .put_object(
            id,
            owner,
            StoredObject {
                obj: s.obj,
                input: s.input,
                history: Vec::new(),
            },
        )
        .await;
}

/// A file entry for a store, when the file exists and is the caller's.
async fn file_entry(
    app: &AppState,
    owner: &str,
    vs: &str,
    fid: &str,
    attributes: Value,
    chunking: Value,
) -> Option<Value> {
    let f = crate::api::files::get(app, fid)
        .await
        .filter(|f| f.owner == owner)?;
    Some(json!({
        "id": fid,
        "object": "vector_store.file",
        "usage_bytes": f.bytes.len(),
        "created_at": now(),
        "vector_store_id": vs,
        "status": "completed",
        "last_error": null,
        "attributes": attributes,
        "chunking_strategy": if chunking.is_null() { json!({"type": "static", "static": {"max_chunk_size_tokens": 800, "chunk_overlap_tokens": 400}}) } else { chunking },
    }))
}

async fn add_files(
    app: &AppState,
    owner: &str,
    vs: &str,
    files: &[(String, Value, Value)],
) -> Result<Vec<Value>, String> {
    let mut added = Vec::new();
    for (fid, attrs, chunking) in files {
        let e = file_entry(app, owner, vs, fid, attrs.clone(), chunking.clone())
            .await
            .ok_or(format!("No file found with id '{fid}'."))?;
        added.push(e);
    }
    let Some(mut s) = app.object.get_object(owner, vs).await else {
        return Err(format!("No vector store found with id '{vs}'."));
    };
    let ids: Vec<String> = added
        .iter()
        .map(|e| e["id"].as_str().unwrap_or("").to_string())
        .collect();
    s.input.retain(|f| !ids.iter().any(|i| f["id"] == json!(i)));
    s.input.extend(added.iter().cloned());
    app.object
        .put_object(
            vs,
            owner,
            StoredObject {
                obj: s.obj,
                input: s.input,
                history: Vec::new(),
            },
        )
        .await;
    refresh(app, owner, vs).await;
    Ok(added)
}

#[derive(Debug, serde::Deserialize, Default)]
pub struct ListQuery {
    #[serde(default)]
    limit: Option<usize>,
    #[serde(default)]
    order: Option<String>,
    #[serde(default)]
    after: Option<String>,
    #[serde(default)]
    filter: Option<String>,
}

fn page(mut items: Vec<Value>, q: &ListQuery) -> Value {
    if q.order.as_deref().unwrap_or("desc") == "desc" {
        items.reverse();
    }
    if let Some(a) = &q.after {
        if let Some(i) = items.iter().position(|x| x["id"] == json!(a)) {
            items.drain(..=i);
        }
    }
    let limit = q.limit.unwrap_or(20).clamp(1, 100);
    let has_more = items.len() > limit;
    items.truncate(limit);
    let id_of = |x: Option<&Value>| x.and_then(|v| v.get("id")).cloned().unwrap_or(Value::Null);
    json!({"object": "list", "data": items, "first_id": id_of(items.first()), "last_id": id_of(items.last()), "has_more": has_more})
}

// ── stores ──

pub async fn create(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    body: Option<Json<Value>>,
) -> Response {
    let b = body.map(|Json(b)| b).unwrap_or(json!({}));
    let owner = principal.agent.id.clone();
    let id = format!("vs_{}", uuid::Uuid::now_v7().simple());
    let t = now();
    let obj = json!({
        "id": id,
        "object": "vector_store",
        "created_at": t,
        "name": b.get("name").cloned().unwrap_or(Value::Null),
        "usage_bytes": 0,
        "file_counts": {"in_progress": 0, "completed": 0, "failed": 0, "cancelled": 0, "total": 0},
        "status": "completed",
        "expires_after": b.get("expires_after").cloned().unwrap_or(Value::Null),
        "expires_at": null,
        "last_active_at": t,
        "metadata": b.get("metadata").cloned().unwrap_or(json!({})),
    });
    app.object
        .put_object(
            &id,
            &owner,
            StoredObject {
                obj,
                input: Vec::new(),
                history: Vec::new(),
            },
        )
        .await;
    let files: Vec<(String, Value, Value)> = b
        .get("file_ids")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str())
                .map(|f| {
                    (
                        f.to_string(),
                        json!({}),
                        b.get("chunking_strategy").cloned().unwrap_or(Value::Null),
                    )
                })
                .collect()
        })
        .unwrap_or_default();
    if let Err(e) = add_files(&app, &owner, &id, &files).await {
        app.object.delete_object(&owner, &id).await;
        return err(StatusCode::NOT_FOUND, &e);
    }
    match get_store(&app, &owner, &id).await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("vector store", &id),
    }
}

pub async fn list(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Query(q): Query<ListQuery>,
) -> Response {
    let items = app
        .object
        .list_objects(&principal.agent.id, "vector_store")
        .await
        .into_iter()
        .map(|(_, s)| s.obj)
        .collect();
    Json(page(items, &q)).into_response()
}

pub async fn retrieve(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    match get_store(&app, &principal.agent.id, &id).await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("vector store", &id),
    }
}

pub async fn modify(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    let owner = principal.agent.id.clone();
    let Some(mut s) = get_store(&app, &owner, &id).await else {
        return not_found("vector store", &id);
    };
    for k in ["name", "metadata", "expires_after"] {
        if let Some(v) = b.get(k) {
            s.obj[k] = v.clone();
        }
    }
    s.obj["last_active_at"] = json!(now());
    app.object
        .put_object(
            &id,
            &owner,
            StoredObject {
                obj: s.obj,
                input: s.input,
                history: Vec::new(),
            },
        )
        .await;
    retrieve(State(app), principal, Path(id)).await
}

pub async fn delete(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    if get_store(&app, &principal.agent.id, &id).await.is_some()
        && app.object.delete_object(&principal.agent.id, &id).await
    {
        Json(json!({"id": id, "object": "vector_store.deleted", "deleted": true})).into_response()
    } else {
        not_found("vector store", &id)
    }
}

// ── files ──

pub async fn add_file(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    if get_store(&app, &principal.agent.id, &id).await.is_none() {
        return not_found("vector store", &id);
    }
    let Some(fid) = b.get("file_id").and_then(|v| v.as_str()) else {
        return err(StatusCode::BAD_REQUEST, "file_id is required");
    };
    let attrs = b.get("attributes").cloned().unwrap_or(json!({}));
    let chunking = b.get("chunking_strategy").cloned().unwrap_or(Value::Null);
    match add_files(
        &app,
        &principal.agent.id,
        &id,
        &[(fid.to_string(), attrs, chunking)],
    )
    .await
    {
        Ok(mut v) => Json(v.remove(0)).into_response(),
        Err(e) => err(StatusCode::NOT_FOUND, &e),
    }
}

pub async fn list_files(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Query(q): Query<ListQuery>,
) -> Response {
    let Some(s) = get_store(&app, &principal.agent.id, &id).await else {
        return not_found("vector store", &id);
    };
    let items = s
        .input
        .into_iter()
        .filter(|f| {
            q.filter
                .as_deref()
                .is_none_or(|st| f["status"] == json!(st))
        })
        .collect();
    Json(page(items, &q)).into_response()
}

pub async fn get_file(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((id, fid)): Path<(String, String)>,
) -> Response {
    match get_store(&app, &principal.agent.id, &id)
        .await
        .and_then(|s| s.input.into_iter().find(|f| f["id"] == json!(fid)))
    {
        Some(f) => Json(f).into_response(),
        None => not_found("vector store file", &fid),
    }
}

pub async fn update_file(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((id, fid)): Path<(String, String)>,
    Json(b): Json<Value>,
) -> Response {
    let owner = principal.agent.id.clone();
    let Some(mut s) = get_store(&app, &owner, &id).await else {
        return not_found("vector store file", &fid);
    };
    if !s.input.iter().any(|f| f["id"] == json!(fid)) {
        return not_found("vector store file", &fid);
    }
    let attrs = b.get("attributes").cloned().unwrap_or(json!({}));
    for f in s.input.iter_mut().filter(|f| f["id"] == json!(fid)) {
        f["attributes"] = attrs.clone();
    }
    app.object
        .put_object(
            &id,
            &owner,
            StoredObject {
                obj: s.obj,
                input: s.input,
                history: Vec::new(),
            },
        )
        .await;
    get_file(State(app), principal, Path((id, fid))).await
}

pub async fn delete_file(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((id, fid)): Path<(String, String)>,
) -> Response {
    let owner = principal.agent.id.clone();
    let Some(mut s) = get_store(&app, &owner, &id).await else {
        return not_found("vector store file", &fid);
    };
    if !s.input.iter().any(|f| f["id"] == json!(fid)) {
        return not_found("vector store file", &fid);
    }
    s.input.retain(|f| f["id"] != json!(fid));
    app.object
        .put_object(
            &id,
            &owner,
            StoredObject {
                obj: s.obj,
                input: s.input,
                history: Vec::new(),
            },
        )
        .await;
    refresh(&app, &owner, &id).await;
    Json(json!({"id": fid, "object": "vector_store.file.deleted", "deleted": true})).into_response()
}

pub async fn file_content(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((id, fid)): Path<(String, String)>,
) -> Response {
    let found = get_store(&app, &principal.agent.id, &id)
        .await
        .is_some_and(|s| s.input.iter().any(|f| f["id"] == json!(fid)));
    let file = crate::api::files::get(&app, &fid).await.filter(|_| found);
    match file {
        Some(f) => Json(json!({
            "object": "vector_store.file_content.page",
            "data": [{"type": "text", "text": String::from_utf8_lossy(&f.bytes)}],
            "has_more": false,
            "next_page": null,
        }))
        .into_response(),
        None => not_found("vector store file", &fid),
    }
}

// ── file batches ──

pub async fn create_batch(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    if get_store(&app, &principal.agent.id, &id).await.is_none() {
        return not_found("vector store", &id);
    }
    let chunking = b.get("chunking_strategy").cloned().unwrap_or(Value::Null);
    let attrs = b.get("attributes").cloned().unwrap_or(json!({}));
    let mut files: Vec<(String, Value, Value)> = b
        .get("file_ids")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str())
                .map(|f| (f.to_string(), attrs.clone(), chunking.clone()))
                .collect()
        })
        .unwrap_or_default();
    for f in b
        .get("files")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
    {
        if let Some(fid) = f.get("file_id").and_then(|v| v.as_str()) {
            files.push((
                fid.to_string(),
                f.get("attributes").cloned().unwrap_or(attrs.clone()),
                f.get("chunking_strategy")
                    .cloned()
                    .unwrap_or(chunking.clone()),
            ));
        }
    }
    if files.is_empty() {
        return err(StatusCode::BAD_REQUEST, "file_ids or files is required");
    }
    let added = match add_files(&app, &principal.agent.id, &id, &files).await {
        Ok(a) => a,
        Err(e) => return err(StatusCode::NOT_FOUND, &e),
    };
    let bid = format!("vsfb_{}", uuid::Uuid::now_v7().simple());
    let n = added.len();
    let obj = json!({
        "id": bid,
        "object": "vector_store.files_batch",
        "created_at": now(),
        "vector_store_id": id,
        "status": "completed",
        "file_counts": {"in_progress": 0, "completed": n, "failed": 0, "cancelled": 0, "total": n},
    });
    app.object
        .put_object(
            &bid,
            &principal.agent.id,
            StoredObject {
                obj: obj.clone(),
                input: added,
                history: Vec::new(),
            },
        )
        .await;
    Json(obj).into_response()
}

async fn get_batch(app: &AppState, owner: &str, id: &str, bid: &str) -> Option<StoredObject> {
    app.object.get_object(owner, bid).await.filter(|s| {
        s.obj["object"] == "vector_store.files_batch" && s.obj["vector_store_id"] == json!(id)
    })
}

pub async fn get_batch_route(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((id, bid)): Path<(String, String)>,
) -> Response {
    match get_batch(&app, &principal.agent.id, &id, &bid).await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("vector store file batch", &bid),
    }
}

/// Batches complete as they are created, so there is nothing to stop.
pub async fn cancel_batch(
    app: State<AppState>,
    principal: AuthPrincipal,
    path: Path<(String, String)>,
) -> Response {
    get_batch_route(app, principal, path).await
}

pub async fn batch_files(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((id, bid)): Path<(String, String)>,
    Query(q): Query<ListQuery>,
) -> Response {
    match get_batch(&app, &principal.agent.id, &id, &bid).await {
        Some(s) => Json(page(s.input, &q)).into_response(),
        None => not_found("vector store file batch", &bid),
    }
}

// ── search ──

/// The hits in a seat's answer, checked against the store's files
/// (`spec.files`: `[{id, filename}]`) and the result cap.
pub fn parse_hits(text: &str, spec: &Value) -> Result<Vec<Value>, String> {
    let max = spec.get("max").and_then(|v| v.as_u64()).unwrap_or(10) as usize;
    let files = spec
        .get("files")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let v: Value = serde_json::from_str(text.trim()).map_err(|_| {
        "answer with JSON: [{\"file\": \"<file id or name>\", \"score\": 0.9, \"text\": \"the passage\"}] best first, [] for none".to_string()
    })?;
    let list = v
        .get("data")
        .or_else(|| v.get("results"))
        .cloned()
        .unwrap_or(v);
    let list = list
        .as_array()
        .ok_or("answer with a JSON list of hits")?
        .clone();
    if list.len() > max {
        return Err(format!("at most {max} hits; got {}", list.len()));
    }
    list.iter()
        .enumerate()
        .map(|(i, h)| {
            let f = h
                .get("file")
                .or_else(|| h.get("file_id"))
                .or_else(|| h.get("filename"))
                .and_then(|v| v.as_str())
                .ok_or(format!("hit {}: `file` (id or name) is required", i + 1))?;
            let file = files
                .iter()
                .find(|x| x["id"] == json!(f) || x["filename"] == json!(f))
                .ok_or(format!("hit {}: `{f}` is not a file of this store", i + 1))?;
            let text = h
                .get("text")
                .or_else(|| h.get("content"))
                .and_then(|v| v.as_str())
                .ok_or(format!("hit {}: `text` (the passage) is required", i + 1))?;
            let score = h
                .get("score")
                .and_then(|v| v.as_f64())
                .unwrap_or(1.0 - i as f64 * 0.01);
            if !(0.0..=1.0).contains(&score) {
                return Err(format!("hit {}: score must be within 0..1", i + 1));
            }
            Ok(json!({
                "file_id": file["id"],
                "filename": file["filename"],
                "score": score,
                "attributes": file.get("attributes").cloned().unwrap_or(json!({})),
                "content": [{"type": "text", "text": text}],
            }))
        })
        .collect()
}

pub async fn search(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    let Some(s) = get_store(&app, &principal.agent.id, &id).await else {
        return not_found("vector store", &id);
    };
    let queries: Vec<String> = match b.get("query") {
        Some(Value::String(q)) => vec![q.clone()],
        Some(Value::Array(a)) => a
            .iter()
            .filter_map(|x| x.as_str().map(String::from))
            .collect(),
        _ => return err(StatusCode::BAD_REQUEST, "query is required"),
    };
    if queries.is_empty() {
        return err(StatusCode::BAD_REQUEST, "query is required");
    }
    let max = b
        .get("max_num_results")
        .and_then(|v| v.as_u64())
        .unwrap_or(10)
        .clamp(1, 50);
    let mut files = Vec::new();
    let mut attach = Vec::new();
    for e in &s.input {
        let fid = e["id"].as_str().unwrap_or("");
        if let Some(f) = crate::api::files::get(&app, fid).await {
            files.push(json!({"id": fid, "filename": f.filename, "attributes": e["attributes"]}));
            attach.push(crate::openai_compat::named_data_url(
                &f.mime,
                Some(&f.filename),
                &crate::openai_compat::b64_encode(&f.bytes),
            ));
        }
    }
    let mut want = format!(
        "search the {} attached file(s) for the query; answer with JSON, best first, at most {max}: [{{\"file\": \"<file name or id>\", \"score\": 0..1, \"text\": \"the matching passage\"}}], [] when nothing matches",
        files.len()
    );
    if let Some(f) = b.get("filters").filter(|f| !f.is_null()) {
        want.push_str(&format!("; only files whose attributes match {f}"));
    }
    let spec = json!({"max": max, "files": files});
    let spec_c = spec.clone();
    let q_c = queries.clone();
    let finish: task::Finish = Box::new(move |answer| {
        let a = match answer {
            Ok(a) => a,
            Err(e) => {
                return Finished::Json(
                    StatusCode::GATEWAY_TIMEOUT,
                    json!({"error": {"message": e, "type": "server_error", "code": "seat_unavailable"}}),
                )
            }
        };
        match parse_hits(&a.raw, &spec_c) {
            Ok(hits) => Finished::Json(
                StatusCode::OK,
                json!({"object": "vector_store.search_results.page", "search_query": q_c, "data": hits, "has_more": false, "next_page": null}),
            ),
            Err(e) => Finished::Json(
                StatusCode::BAD_GATEWAY,
                json!({"error": {"message": e, "type": "server_error", "code": "bad_answer"}}),
            ),
        }
    });
    refresh(&app, &principal.agent.id, &id).await;
    task::run(
        app,
        principal,
        headers,
        "vector_stores.search",
        None,
        queries.join("\n"),
        attach,
        want,
        false,
        spec,
        Delivery::Json,
        finish,
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hits_name_store_files() {
        let spec = json!({"max": 2, "files": [{"id": "file-1", "filename": "a.txt"}]});
        let h = parse_hits(r#"[{"file": "a.txt", "score": 0.8, "text": "x"}]"#, &spec).unwrap();
        assert_eq!(h[0]["file_id"], "file-1");
        assert!(parse_hits(r#"[{"file": "b.txt", "text": "x"}]"#, &spec)
            .unwrap_err()
            .contains("not a file"));
        assert!(parse_hits("[]", &spec).unwrap().is_empty());
        assert!(parse_hits(r#"[{"file":"a.txt","text":"1"},{"file":"a.txt","text":"2"},{"file":"a.txt","text":"3"}]"#, &spec).is_err());
    }
}
