//! Graders and Evals, with the seat where a model would be.
//!
//! - Graders: `string_check` and `text_similarity` are computed here;
//!   model graders (`label_model`, `score_model`) and `python` graders are
//!   seat tasks that answer a score or label; `multi` averages.
//! - Evals: CRUD; a run samples each data row through the chat pipeline
//!   when its data source asks for sampling, then grades every row with
//!   the eval's testing criteria; output items and counts as OpenAI
//!   shapes them.
//!
//! Fine-tuning is not ported: this server trains nothing, so a "job"
//! that turns an acknowledgement into an `ft:` model name would claim a
//! provenance the model does not have. Evals and runs persist through
//! the ObjectRepository; a run in flight at restart stays `in_progress`
//! (cancel it or delete it) - the abort handles are process-local.

// Handlers return the HTTP error response itself as their `Err`.
#![allow(clippy::result_large_err)]

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::{json, Value};

use crate::api::task::{self, Delivery, Finished};
use crate::auth::AuthPrincipal;
use crate::storage::traits::StoredObject;
use crate::storage::AppState;

fn now() -> i64 {
    chrono::Utc::now().timestamp()
}

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

#[derive(Debug, serde::Deserialize, Default)]
pub struct ListQuery {
    #[serde(default)]
    limit: Option<usize>,
    #[serde(default)]
    after: Option<String>,
    #[serde(default)]
    order: Option<String>,
}

fn page(mut items: Vec<Value>, q: &ListQuery, default_order: &str) -> Value {
    if q.order.as_deref().unwrap_or(default_order) == "desc" {
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

/// Abort handles for the eval runs this process is running.
fn running() -> &'static Mutex<HashMap<String, tokio::task::AbortHandle>> {
    static R: OnceLock<Mutex<HashMap<String, tokio::task::AbortHandle>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(HashMap::new()))
}

fn abort_running(id: &str) -> bool {
    if let Some(h) = running().lock().unwrap().remove(id) {
        h.abort();
        true
    } else {
        false
    }
}

// ── templates and graders ──

/// Fill `{{item.x}}` / `{{sample.output_text}}` (dotted paths) from the
/// row and its sample.
pub fn render(t: &str, item: &Value, sample: &Value) -> String {
    let mut out = String::new();
    let mut rest = t;
    while let Some(i) = rest.find("{{") {
        out.push_str(&rest[..i]);
        let Some(j) = rest[i..].find("}}") else {
            out.push_str(&rest[i..]);
            return out;
        };
        let path = rest[i + 2..i + j].trim();
        let mut parts = path.split('.');
        let root = match parts.next() {
            Some("item") => item,
            Some("sample") => sample,
            _ => &Value::Null,
        };
        let mut v = root;
        for p in parts {
            v = match v {
                Value::Array(a) => p
                    .parse::<usize>()
                    .ok()
                    .and_then(|n| a.get(n))
                    .unwrap_or(&Value::Null),
                _ => v.get(p).unwrap_or(&Value::Null),
            };
        }
        out.push_str(&match v {
            Value::String(s) => s.clone(),
            Value::Null => String::new(),
            o => o.to_string(),
        });
        rest = &rest[i + j + 2..];
    }
    out.push_str(rest);
    out
}

/// Similarity in 0..1 from edit distance (fuzzy_match), shared by every
/// text_similarity metric here.
pub fn similarity(a: &str, b: &str) -> f64 {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    if a.is_empty() && b.is_empty() {
        return 1.0;
    }
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    for (i, ca) in a.iter().enumerate() {
        let mut cur = vec![i + 1];
        for (j, cb) in b.iter().enumerate() {
            let sub = prev[j] + (ca != cb) as usize;
            cur.push(sub.min(prev[j + 1] + 1).min(cur[j] + 1));
        }
        prev = cur;
    }
    1.0 - prev[b.len()] as f64 / a.len().max(b.len()) as f64
}

/// A grader's verdict: score, pass/fail, and errors.
pub struct Grade {
    pub score: f64,
    pub passed: bool,
    pub detail: Value,
}

/// Grade one row. Model and python graders become one seat task each.
pub async fn grade(
    g: &Value,
    item: &Value,
    sample: &Value,
    app: &AppState,
    principal: &AuthPrincipal,
    headers: &HeaderMap,
) -> Result<Grade, String> {
    let kind = g["type"].as_str().unwrap_or("");
    match kind {
        "string_check" => {
            let input = render(g["input"].as_str().unwrap_or(""), item, sample);
            let reference = render(g["reference"].as_str().unwrap_or(""), item, sample);
            let ok = match g["operation"].as_str().unwrap_or("eq") {
                "eq" => input == reference,
                "ne" => input != reference,
                "like" => input.contains(&reference),
                "ilike" => input.to_lowercase().contains(&reference.to_lowercase()),
                o => return Err(format!("unknown string_check operation {o}")),
            };
            Ok(Grade {
                score: ok as u8 as f64,
                passed: ok,
                detail: json!({}),
            })
        }
        "text_similarity" => {
            let input = render(g["input"].as_str().unwrap_or(""), item, sample);
            let reference = render(g["reference"].as_str().unwrap_or(""), item, sample);
            let score = similarity(&input, &reference);
            let threshold = g["pass_threshold"].as_f64().unwrap_or(0.5);
            Ok(Grade {
                score,
                passed: score >= threshold,
                detail: json!({"evaluation_metric": g["evaluation_metric"]}),
            })
        }
        "multi" => {
            let subs = g["graders"].as_object().cloned().unwrap_or_default();
            let mut total = 0.0;
            for (_, sg) in &subs {
                total += Box::pin(grade(sg, item, sample, app, principal, headers))
                    .await?
                    .score;
            }
            let score = if subs.is_empty() {
                0.0
            } else {
                total / subs.len() as f64
            };
            Ok(Grade {
                score,
                passed: score >= 0.5,
                detail: json!({}),
            })
        }
        "label_model" | "score_model" | "python" => {
            seat_grade(g, item, sample, app, principal, headers).await
        }
        o => Err(format!("unknown grader type {o}")),
    }
}

/// A grader the seat applies: it answers JSON `{"score": x}` or
/// `{"label": "..."}`.
async fn seat_grade(
    g: &Value,
    item: &Value,
    sample: &Value,
    app: &AppState,
    principal: &AuthPrincipal,
    headers: &HeaderMap,
) -> Result<Grade, String> {
    let kind = g["type"].as_str().unwrap_or("");
    let rendered = match kind {
        "python" => format!(
            "Grader source:\n{}\n\nitem: {item}\nsample: {sample}",
            g["source"].as_str().unwrap_or("")
        ),
        _ => g["input"]
            .as_array()
            .map(|msgs| {
                msgs.iter()
                    .map(|m| {
                        let c = m["content"]
                            .as_str()
                            .map(String::from)
                            .unwrap_or_else(|| m["content"].to_string());
                        format!(
                            "[{}] {}",
                            m["role"].as_str().unwrap_or("user"),
                            render(&c, item, sample)
                        )
                    })
                    .collect::<Vec<_>>()
                    .join("\n\n")
            })
            .unwrap_or_default(),
    };
    let (want, spec) = match kind {
        "label_model" => {
            let labels = g["labels"].clone();
            (format!("grade as the messages ask: answer JSON {{\"label\": one of {labels}}}"), json!({"labels": labels}))
        }
        "score_model" => {
            let range = g["range"].as_array().cloned().unwrap_or_else(|| vec![json!(0), json!(1)]);
            (format!("grade as the messages ask: answer JSON {{\"score\": a number in {}}}", Value::Array(range.clone())), json!({"range": range}))
        }
        _ => ("run the grader on the item and sample (as Python's grade(sample, item) would): answer JSON {\"score\": a number}".to_string(), json!({})),
    };
    let (tx, rx) = tokio::sync::oneshot::channel();
    let finish: task::Finish = Box::new(move |a| {
        let _ = tx.send(a.map(|a| a.raw));
        Finished::Json(StatusCode::OK, json!({}))
    });
    let resp = task::run(
        app.clone(),
        principal.clone(),
        headers.clone(),
        "graders",
        g["model"].as_str(),
        rendered,
        Vec::new(),
        want,
        false,
        spec,
        Delivery::Json,
        finish,
    )
    .await;
    let _ = axum::body::to_bytes(resp.into_body(), usize::MAX).await;
    let raw = rx.await.map_err(|_| "no answer".to_string())??;
    let v: Value = serde_json::from_str(raw.trim())
        .map_err(|_| format!("grader answer is not JSON: {raw}"))?;
    match kind {
        "label_model" => {
            let label = v["label"].as_str().unwrap_or("").to_string();
            let passed = g["passing_labels"]
                .as_array()
                .is_some_and(|p| p.iter().any(|x| x == &json!(label)));
            Ok(Grade {
                score: passed as u8 as f64,
                passed,
                detail: json!({"label": label}),
            })
        }
        _ => {
            let score = v["score"].as_f64().ok_or("grader answer has no score")?;
            let threshold = g["pass_threshold"].as_f64().unwrap_or(0.5);
            Ok(Grade {
                score,
                passed: score >= threshold,
                detail: json!({}),
            })
        }
    }
}

/// Check a seat's grading answer before it is delivered.
pub fn check_grade(text: &str, spec: &Value) -> Result<(), String> {
    let v: Value = serde_json::from_str(text.trim())
        .map_err(|_| "answer with JSON: {\"score\": 0.8} or {\"label\": \"...\"}".to_string())?;
    if let Some(labels) = spec.get("labels").and_then(|l| l.as_array()) {
        let l = v["label"]
            .as_str()
            .ok_or("answer with {\"label\": \"...\"}")?;
        if !labels.iter().any(|x| x == &json!(l)) {
            return Err(format!(
                "label must be one of {}",
                Value::Array(labels.clone())
            ));
        }
        return Ok(());
    }
    let s = v["score"]
        .as_f64()
        .ok_or("answer with {\"score\": <number>}")?;
    if let Some(r) = spec.get("range").and_then(|r| r.as_array()) {
        let (lo, hi) = (
            r.first().and_then(|x| x.as_f64()).unwrap_or(0.0),
            r.get(1).and_then(|x| x.as_f64()).unwrap_or(1.0),
        );
        if s < lo || s > hi {
            return Err(format!("score must be within {lo}..{hi}"));
        }
    }
    Ok(())
}

/// `POST /v1/fine_tuning/alpha/graders/run`
pub async fn graders_run(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Json(b): Json<Value>,
) -> Response {
    let g = b.get("grader").cloned().unwrap_or(Value::Null);
    let item = b.get("item").cloned().unwrap_or(json!({}));
    let sample_text = b.get("model_sample").cloned().unwrap_or(json!(""));
    let sample =
        json!({"output_text": sample_text, "choices": [{"message": {"content": sample_text}}]});
    let started = std::time::Instant::now();
    match grade(&g, &item, &sample, &app, &principal, &headers).await {
        Ok(r) => Json(json!({
            "reward": r.score,
            "metadata": {"name": g["name"], "type": g["type"], "errors": {}, "execution_time": started.elapsed().as_secs_f64(),
                         "scores": {}, "token_usage": null, "sampled_model_name": null},
            "sub_rewards": {},
            "model_grader_token_usage_per_model": {},
        }))
        .into_response(),
        Err(e) => err(StatusCode::BAD_REQUEST, &e),
    }
}

/// `POST /v1/fine_tuning/alpha/graders/validate`
pub async fn graders_validate(Json(b): Json<Value>) -> Response {
    let g = b.get("grader").cloned().unwrap_or(Value::Null);
    match g["type"].as_str() {
        Some("string_check" | "text_similarity" | "label_model" | "score_model" | "python" | "multi") => {
            Json(json!({"grader": g})).into_response()
        }
        _ => err(StatusCode::BAD_REQUEST, "grader.type must be string_check, text_similarity, label_model, score_model, python or multi"),
    }
}

// ── evals ──

async fn get_eval(app: &AppState, owner: &str, id: &str) -> Option<StoredObject> {
    app.object
        .get_object(owner, id)
        .await
        .filter(|s| s.obj["object"] == "eval")
}

pub async fn create_eval(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Json(b): Json<Value>,
) -> Response {
    let Some(criteria) = b.get("testing_criteria").and_then(|v| v.as_array()) else {
        return err(StatusCode::BAD_REQUEST, "testing_criteria is required");
    };
    let id = format!("eval_{}", uuid::Uuid::now_v7().simple());
    let criteria: Vec<Value> = criteria
        .iter()
        .map(|c| {
            let mut c = c.clone();
            if c.get("name").is_none() {
                c["name"] = c["type"].clone();
            }
            c
        })
        .collect();
    let obj = json!({
        "id": id,
        "object": "eval",
        "name": b.get("name").cloned().unwrap_or(Value::Null),
        "data_source_config": b.get("data_source_config").cloned().unwrap_or(json!({"type": "custom", "schema": {}})),
        "testing_criteria": criteria,
        "created_at": now(),
        "metadata": b.get("metadata").cloned().unwrap_or(json!({})),
    });
    app.object
        .put_object(
            &id,
            &principal.agent.id,
            StoredObject {
                obj: obj.clone(),
                input: Vec::new(),
                history: Vec::new(),
            },
        )
        .await;
    Json(obj).into_response()
}

pub async fn list_evals(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Query(q): Query<ListQuery>,
) -> Response {
    let items = app
        .object
        .list_objects(&principal.agent.id, "eval")
        .await
        .into_iter()
        .map(|(_, s)| s.obj)
        .collect();
    Json(page(items, &q, "asc")).into_response()
}

pub async fn get_eval_route(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    match get_eval(&app, &principal.agent.id, &id).await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("eval", &id),
    }
}

pub async fn update_eval(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    if get_eval(&app, &principal.agent.id, &id).await.is_none() {
        return not_found("eval", &id);
    }
    app.object
        .update_object(&id, &move |s| {
            for k in ["name", "metadata"] {
                if let Some(v) = b.get(k) {
                    s.obj[k] = v.clone();
                }
            }
        })
        .await;
    match get_eval(&app, &principal.agent.id, &id).await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("eval", &id),
    }
}

pub async fn delete_eval(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(id): Path<String>,
) -> Response {
    if get_eval(&app, &principal.agent.id, &id).await.is_some() {
        app.object.delete_object(&principal.agent.id, &id).await;
        Json(json!({"object": "eval.deleted", "deleted": true, "eval_id": id})).into_response()
    } else {
        not_found("eval", &id)
    }
}

/// Rows of a run's data source: `{item, sample?}` each.
async fn rows(app: &AppState, ds: &Value, owner: &str) -> Result<Vec<Value>, String> {
    let src = &ds["source"];
    match src["type"].as_str().unwrap_or("") {
        "file_content" => Ok(src["content"].as_array().cloned().unwrap_or_default()),
        "file_id" => {
            let id = src["id"].as_str().unwrap_or("");
            let f = crate::api::files::get(app, id)
                .await
                .filter(|f| f.owner == owner)
                .ok_or(format!("No file found with id '{id}'."))?;
            String::from_utf8_lossy(&f.bytes)
                .lines()
                .filter(|l| !l.trim().is_empty())
                .map(|l| serde_json::from_str(l).map_err(|e| e.to_string()))
                .collect()
        }
        // Stored completions are process-local by design (the chat
        // pipeline keeps them for replay); a run reads what this process
        // has.
        "stored_completions" => Ok(crate::api::stored::list(owner, "chat.completion")
            .into_iter()
            .map(|(_, s)| json!({"item": {"input": s.input}, "sample": {"output_text": s.obj.pointer("/choices/0/message/content").cloned().unwrap_or(Value::Null)}}))
            .collect()),
        o => Err(format!("unsupported data source {o}")),
    }
}

pub async fn create_run(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    headers: HeaderMap,
    Path(eval_id): Path<String>,
    Json(b): Json<Value>,
) -> Response {
    let owner = principal.agent.id.clone();
    let Some(ev) = get_eval(&app, &owner, &eval_id).await else {
        return not_found("eval", &eval_id);
    };
    let ds = b.get("data_source").cloned().unwrap_or(Value::Null);
    let data = match rows(&app, &ds, &owner).await {
        Ok(r) => r,
        Err(e) => return err(StatusCode::BAD_REQUEST, &e),
    };
    let id = format!("evalrun_{}", uuid::Uuid::now_v7().simple());
    let criteria = ev.obj["testing_criteria"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    let obj = json!({
        "id": id,
        "object": "eval.run",
        "eval_id": eval_id,
        "name": b.get("name").cloned().unwrap_or(json!(id)),
        "status": "queued",
        "model": ds.get("model").cloned().unwrap_or(Value::Null),
        "data_source": ds,
        "created_at": now(),
        "result_counts": {"total": data.len(), "passed": 0, "failed": 0, "errored": 0},
        "per_model_usage": [],
        "per_testing_criteria_results": criteria.iter().map(|c| json!({"testing_criteria": c["name"], "passed": 0, "failed": 0})).collect::<Vec<_>>(),
        "report_url": null,
        "error": null,
        "metadata": b.get("metadata").cloned().unwrap_or(json!({})),
    });
    app.object
        .put_object(
            &id,
            &owner,
            StoredObject {
                obj: obj.clone(),
                input: Vec::new(),
                history: Vec::new(),
            },
        )
        .await;
    let rid = id.clone();
    let task = tokio::spawn(async move {
        app.object
            .update_object(&rid, &|s| s.obj["status"] = json!("in_progress"))
            .await;
        let template = ds
            .pointer("/input_messages/template")
            .and_then(|t| t.as_array())
            .cloned();
        for (i, row) in data.into_iter().enumerate() {
            let item = row.get("item").cloned().unwrap_or_else(|| row.clone());
            let mut sample = row.get("sample").cloned().unwrap_or(Value::Null);
            let mut errored = None;
            // Sampling: the template rendered per row, answered by the seat.
            if let Some(t) = &template {
                let msgs: Vec<Value> = t
                    .iter()
                    .map(|m| {
                        let c = m["content"].as_str().map(String::from).unwrap_or_else(|| m["content"].to_string());
                        json!({"role": m["role"].as_str().unwrap_or("user"), "content": render(&c, &item, &Value::Null)})
                    })
                    .collect();
                let mut h = headers.clone();
                if let Ok(v) = axum::http::HeaderValue::from_str(&format!("eval:{rid}:{i}")) {
                    h.insert("x-openhuman-session-id", v);
                }
                h.remove("x-openhuman-mode");
                let body = json!({"model": ds["model"], "messages": msgs, "stream": false});
                match serde_json::from_value(body) {
                    Err(e) => errored = Some(json!(e.to_string())),
                    Ok(req) => {
                        let resp = crate::api::openai::chat_completions(
                            State(app.clone()),
                            principal.clone(),
                            h,
                            Json(req),
                        )
                        .await;
                        let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
                            .await
                            .unwrap_or_default();
                        match serde_json::from_str::<Value>(String::from_utf8_lossy(&bytes).trim())
                        {
                            Ok(v) if v.pointer("/choices/0/message").is_some() => {
                                let text = v
                                    .pointer("/choices/0/message/content")
                                    .cloned()
                                    .unwrap_or(json!(""));
                                sample = json!({"output_text": text, "choices": v["choices"], "model": v["model"], "usage": v["usage"]});
                            }
                            Ok(v) => {
                                errored = Some(
                                    v.pointer("/error/message")
                                        .cloned()
                                        .unwrap_or(json!("sampling failed")),
                                )
                            }
                            Err(e) => errored = Some(json!(e.to_string())),
                        }
                    }
                }
            }
            let mut results = Vec::new();
            let mut all_pass = errored.is_none();
            for c in &criteria {
                match grade(c, &item, &sample, &app, &principal, &headers).await {
                    Ok(g) => {
                        all_pass &= g.passed;
                        let name = c["name"].clone();
                        let passed = g.passed;
                        app.object
                            .update_object(&rid, &move |s| {
                                for r in s.obj["per_testing_criteria_results"]
                                    .as_array_mut()
                                    .into_iter()
                                    .flatten()
                                {
                                    if r["testing_criteria"] == name {
                                        let k = if passed { "passed" } else { "failed" };
                                        r[k] = json!(r[k].as_u64().unwrap_or(0) + 1);
                                    }
                                }
                            })
                            .await;
                        results.push(json!({"name": c["name"], "type": c["type"], "score": g.score, "passed": g.passed, "sample": null, "detail": g.detail}));
                    }
                    Err(e) => {
                        all_pass = false;
                        errored = Some(json!(e));
                    }
                }
            }
            let status = if errored.is_some() {
                "fail"
            } else if all_pass {
                "pass"
            } else {
                "fail"
            };
            let out = json!({
                "id": format!("outputitem_{}", uuid::Uuid::now_v7().simple()),
                "object": "eval.run.output_item",
                "eval_id": eval_id,
                "run_id": rid,
                "created_at": now(),
                "status": status,
                "datasource_item_id": i,
                "datasource_item": item,
                "results": results,
                "sample": if sample.is_null() { Value::Null } else { json!({"input": [], "output": [{"role": "assistant", "content": sample["output_text"]}], "model": sample["model"], "usage": sample["usage"], "error": errored, "finish_reason": "stop", "temperature": 1.0, "top_p": 1.0, "seed": null, "max_completion_tokens": null}) },
            });
            app.object
                .update_object(&rid, &move |s| {
                    let k = if errored.is_some() {
                        "errored"
                    } else if all_pass {
                        "passed"
                    } else {
                        "failed"
                    };
                    s.obj["result_counts"][k] =
                        json!(s.obj["result_counts"][k].as_u64().unwrap_or(0) + 1);
                    s.input.push(out.clone());
                })
                .await;
        }
        app.object
            .update_object(&rid, &|s| s.obj["status"] = json!("completed"))
            .await;
        running().lock().unwrap().remove(&rid);
    });
    running()
        .lock()
        .unwrap()
        .insert(id.clone(), task.abort_handle());
    Json(obj).into_response()
}

async fn get_run(app: &AppState, owner: &str, eval_id: &str, run: &str) -> Option<StoredObject> {
    app.object
        .get_object(owner, run)
        .await
        .filter(|s| s.obj["object"] == "eval.run" && s.obj["eval_id"] == json!(eval_id))
}

pub async fn list_runs(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path(eval_id): Path<String>,
    Query(q): Query<ListQuery>,
) -> Response {
    let items = app
        .object
        .list_objects(&principal.agent.id, "eval.run")
        .await
        .into_iter()
        .map(|(_, s)| s.obj)
        .filter(|o| o["eval_id"] == json!(eval_id))
        .collect();
    Json(page(items, &q, "asc")).into_response()
}

pub async fn get_run_route(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((eval_id, run)): Path<(String, String)>,
) -> Response {
    match get_run(&app, &principal.agent.id, &eval_id, &run).await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("eval run", &run),
    }
}

pub async fn cancel_run(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((eval_id, run)): Path<(String, String)>,
) -> Response {
    if get_run(&app, &principal.agent.id, &eval_id, &run)
        .await
        .is_none()
    {
        return not_found("eval run", &run);
    }
    if abort_running(&run) {
        app.object
            .update_object(&run, &|s| s.obj["status"] = json!("canceled"))
            .await;
    }
    match get_run(&app, &principal.agent.id, &eval_id, &run).await {
        Some(s) => Json(s.obj).into_response(),
        None => not_found("eval run", &run),
    }
}

pub async fn delete_run(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((eval_id, run)): Path<(String, String)>,
) -> Response {
    if get_run(&app, &principal.agent.id, &eval_id, &run)
        .await
        .is_some()
    {
        abort_running(&run);
        app.object.delete_object(&principal.agent.id, &run).await;
        Json(json!({"object": "eval.run.deleted", "deleted": true, "run_id": run})).into_response()
    } else {
        not_found("eval run", &run)
    }
}

#[derive(Debug, serde::Deserialize, Default)]
pub struct ItemsQuery {
    #[serde(default)]
    limit: Option<usize>,
    #[serde(default)]
    after: Option<String>,
    #[serde(default)]
    order: Option<String>,
    #[serde(default)]
    status: Option<String>,
}

pub async fn list_output_items(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((eval_id, run)): Path<(String, String)>,
    Query(q): Query<ItemsQuery>,
) -> Response {
    let Some(s) = get_run(&app, &principal.agent.id, &eval_id, &run).await else {
        return not_found("eval run", &run);
    };
    let items = s
        .input
        .into_iter()
        .filter(|o| {
            q.status
                .as_deref()
                .is_none_or(|st| o["status"] == json!(st))
        })
        .collect();
    let lq = ListQuery {
        limit: q.limit,
        after: q.after,
        order: q.order,
    };
    Json(page(items, &lq, "asc")).into_response()
}

pub async fn get_output_item(
    State(app): State<AppState>,
    principal: AuthPrincipal,
    Path((eval_id, run, item)): Path<(String, String, String)>,
) -> Response {
    match get_run(&app, &principal.agent.id, &eval_id, &run)
        .await
        .and_then(|s| s.input.into_iter().find(|o| o["id"] == json!(item)))
    {
        Some(o) => Json(o).into_response(),
        None => not_found("output item", &item),
    }
}
