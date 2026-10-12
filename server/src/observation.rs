//! Request Observation — captures the raw HTTP request for analysis.
//!
//! This module intercepts `POST /v1/chat/completions` requests and writes
//! a complete JSON fixture to `observations/` on disk. The fixture contains
//! the raw request body (as-sent by the agent), sanitized headers, and
//! metadata about when the request was received.
//!
//! # Design
//!
//! - Implemented as an Axum middleware layer (runs before the handler).
//! - Reads the raw request body bytes **before** Axum deserializes it,
//!   so unknown fields (`tool_choice`, `metadata`, future fields) are
//!   preserved exactly as sent.
//! - Replaces the body back into the request so downstream handlers
//!   see the original data — **no behavioral change**.
//! - API keys / Authorization values are masked: only `Bearer ***`
//!   or `ohk_****` (first 4 chars) is recorded.
//! - Each request generates one file: `observations/YYYY-MM-DD-HHMMSS-NNN.json`
//!
//! # When to Enable
//!
//! Observation is always on. The overhead is minimal (one file write
//! per request). In production, this can be gated behind an env var
//! `OPENHUMAN_OBSERVATION=off`.

use std::collections::BTreeMap;
use std::path::Path;

use axum::body::Body;
use axum::extract::Request;
use axum::http::HeaderMap;
use axum::middleware::Next;
use axum::response::Response;
use chrono::{DateTime, Utc};
use serde::Serialize;
use serde_json::Value;
use uuid::Uuid;

/// The observation fixture written to disk.
#[derive(Debug, Serialize)]
struct ObservationFixture {
    /// ISO-8601 timestamp of when the request was received.
    timestamp: DateTime<Utc>,
    /// Unique observation ID (UUIDv7-based).
    observation_id: String,
    /// HTTP method (always POST for chat completions).
    method: String,
    /// Request URI path.
    uri: String,
    /// Sanitized headers — sensitive values masked.
    headers: BTreeMap<String, String>,
    /// Raw request body as parsed JSON (preserves all fields, known or unknown).
    body: Value,
    /// Whether the body failed to parse as JSON (raw string fallback).
    body_parse_error: Option<String>,
}

/// Middleware: observe and record the raw request, then pass through.
///
/// This runs on the `/v1/chat/completions` route. It reads the body,
/// writes an observation file, then reconstructs the request with the
/// original body so the handler sees no difference.
pub async fn observe_request(request: Request, next: Next) -> Response {
    // Only observe POST to /v1/chat/completions.
    let path = request.uri().path().to_string();
    let method = request.method().to_string();
    let is_chat_completions = path == "/v1/chat/completions" && method == "POST";

    if !is_chat_completions {
        return next.run(request).await;
    }

    // ── Extract body bytes ──
    let (parts, body) = request.into_parts();
    let body_bytes = axum::body::to_bytes(body, usize::MAX)
        .await
        .unwrap_or_default();

    // ── Parse body as JSON (preserve all fields) ──
    let body_str = String::from_utf8_lossy(&body_bytes);
    let (body_value, body_parse_error) = match serde_json::from_str::<Value>(&body_str) {
        Ok(v) => (v, None),
        Err(e) => (
            Value::String(body_str.to_string()),
            Some(format!("Failed to parse body as JSON: {}", e)),
        ),
    };

    // ── Sanitize headers ──
    let headers = sanitize_headers(&parts.headers);

    // ── Build fixture ──
    let now = Utc::now();
    let fixture = ObservationFixture {
        timestamp: now,
        observation_id: format!("obs_{}", Uuid::now_v7().simple()),
        method: method.clone(),
        uri: path.clone(),
        headers,
        body: body_value,
        body_parse_error,
    };

    // ── Write to disk (non-blocking — don't slow down the request) ──
    let fixture_clone = fixture.observation_id.clone();
    let now_clone = now;
    let fixture_json = serde_json::to_string_pretty(&fixture).unwrap_or_default();
    tokio::spawn(async move {
        write_fixture(&now_clone, &fixture_clone, &fixture_json);
    });

    // ── Reconstruct request with original body ──
    let request = Request::from_parts(parts, Body::from(body_bytes));
    next.run(request).await
}

/// Sanitize HTTP headers — mask sensitive values.
///
/// - `Authorization`: `Bearer ***` (never the actual key)
/// - `x-api-key` / `api_key`: first 4 chars + `****`
/// - `Cookie`: `***`
/// - All others: recorded as-is
fn sanitize_headers(headers: &HeaderMap) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();

    for (name, value) in headers.iter() {
        let key = name.as_str().to_string();
        let val_str = value.to_str().unwrap_or("<binary>").to_string();

        let masked = match key.to_lowercase().as_str() {
            "authorization" => {
                if val_str.starts_with("Bearer ") {
                    "Bearer ***".to_string()
                } else {
                    "***".to_string()
                }
            }
            "x-api-key" | "api_key" | "api-key" => {
                if val_str.len() > 4 {
                    format!("{}****", &val_str[..4])
                } else {
                    "****".to_string()
                }
            }
            "cookie" | "set-cookie" | "acl-token" => "***".to_string(),
            _ => val_str,
        };

        map.insert(key, masked);
    }

    map
}

/// Write the observation fixture to disk.
///
/// File path: `observations/YYYY-MM-DD-HHMMSS-NNN.json`
/// where NNN is the last 3 chars of the observation ID for uniqueness.
fn write_fixture(timestamp: &DateTime<Utc>, obs_id: &str, json: &str) {
    let date = timestamp.format("%Y-%m-%d").to_string();
    let time = timestamp.format("%H%M%S").to_string();
    let suffix = &obs_id[obs_id.len().saturating_sub(3)..];
    let filename = format!("{}-{}-{}.json", date, time, suffix);

    let dir = Path::new("observations");
    if let Err(e) = std::fs::create_dir_all(dir) {
        tracing::warn!("Failed to create observations/ dir: {}", e);
        return;
    }

    let path = dir.join(&filename);
    if let Err(e) = std::fs::write(&path, json) {
        tracing::warn!("Failed to write observation {}: {}", path.display(), e);
    } else {
        tracing::info!("Observation written: {}", path.display());
    }
}
