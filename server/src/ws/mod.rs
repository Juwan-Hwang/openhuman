//! WebSocket Human Gateway — `/ws` endpoint.
//!
//! Phase 6: Realtime message routing layer.
//!
//! ```text
//!   Agent Client
//!       ↓ POST /v1/chat/completions
//!   OpenHuman Server
//!       ├── MessageRepository       (stores agent's message)
//!       ├── ReplyRegistry            (registers SSE reply channel)
//!       └── ConnectionRegistry       (pushes message.received to human)
//!                                        ↓
//!                                    Human Client (WS, multi-device)
//!                                        ↓ reply.send
//!   OpenHuman Server
//!       ├── ReplyRegistry            (delivers to SSE)
//!       └── MessageRepository        (stores human's reply)
//!       ↓ SSE chunks
//!   Agent Client
//! ```

pub mod handler;
pub mod protocol;
pub mod registry;

pub use handler::ws_handler;
pub use registry::ConnectionRegistry;
