//! API Gateway — HTTP routes for OpenAI-compatible API + mock human endpoint.
//!
//! Phase 3: `POST /v1/chat/completions` (streaming + non-streaming)
//!          `POST /v1/mock/human-reply` (simulate human response)
//! Phase 10: `GET /v1/replies/{invocation_id}` (async reply polling)

pub mod adapters;
pub mod audio;
pub mod completions;
pub mod files;
pub mod history;
pub mod images;
pub mod library;
pub mod mock;
pub mod openai;
pub mod replies;
pub mod room_ingress;
pub mod rooms;
pub mod stored;
pub mod task;
pub mod webhooks;
