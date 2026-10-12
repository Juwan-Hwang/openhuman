//! Authentication middleware — Bearer API Key → AuthPrincipal.
//!
//! Flow:
//!   Authorization: Bearer <api_key>
//!     → validate key via IdentityRepository
//!     → resolve AgentIdentity + bound HumanIdentity
//!     → inject AuthPrincipal into request extension

use axum::extract::Request;
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{IntoResponse, Json, Response};
use serde_json::json;

use crate::storage::AppState;

/// Re-export so handlers can use `crate::auth::AuthPrincipal`.
pub use crate::state::AuthPrincipal;

/// Auth middleware — checks `Authorization: Bearer <key>`.
///
/// Called via `from_fn_with_state(state, require_api_key)`.
pub async fn require_api_key(
    state: axum::extract::State<AppState>,
    mut request: Request,
    next: Next,
) -> Response {
    let auth_header = request
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok());

    let raw_key = match auth_header {
        Some(h) if h.starts_with("Bearer ") => &h[7..],
        _ => {
            return auth_error(
                StatusCode::UNAUTHORIZED,
                "missing_api_key",
                "Missing or invalid Authorization header. Expected: Bearer <key>",
            )
        }
    };

    let principal = state.identity.resolve_principal(raw_key).await;

    let principal = match principal {
        Some(p) => p,
        None => {
            return auth_error(
                StatusCode::UNAUTHORIZED,
                "invalid_api_key",
                "The provided API key is not recognized.",
            )
        }
    };

    request.extensions_mut().insert(principal);
    next.run(request).await
}

/// Produce an OpenAI-formatted error response.
fn auth_error(status: StatusCode, code: &str, message: &str) -> Response {
    (
        status,
        Json(json!({
            "error": {
                "message": message,
                "type": "invalid_request_error",
                "code": code
            }
        })),
    )
        .into_response()
}

/// Axum extractor — pulls `AuthPrincipal` from request extensions.
#[axum::async_trait]
impl<S> axum::extract::FromRequestParts<S> for AuthPrincipal
where
    S: Send + Sync,
{
    type Rejection = (StatusCode, Json<serde_json::Value>);

    async fn from_request_parts(
        parts: &mut axum::http::request::Parts,
        _state: &S,
    ) -> Result<Self, Self::Rejection> {
        parts.extensions.get::<AuthPrincipal>().cloned().ok_or((
            StatusCode::UNAUTHORIZED,
            Json(json!({
                "error": {
                    "message": "Authentication required.",
                    "type": "invalid_request_error",
                    "code": "no_principal"
                }
            })),
        ))
    }
}
