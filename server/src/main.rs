//! OpenHuman Server — entry point.
//!
//! Phase 5: PostgreSQL Persistence + WebSocket Human Gateway.
//!
//! The backend is selected by the `OPENHUMAN_BACKEND` env var:
//!   - `memory`  (default) — in-memory store, no external deps
//!   - `postgres`            — PostgreSQL + SQLx, requires `DATABASE_URL`
//!
//! ```text
//! Agent Client → POST /v1/chat/completions → OpenHuman Server
//!      ↓ (SSE keepalive while waiting)
//! Human Client → WS /ws (authenticate → receive message → send reply)
//!      ↓
//! Agent receives SSE chunks → [DONE]
//! ```

use openhuman_server::build_router;
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::postgres::{InMemoryReplyRegistry, PostgresStore};
use openhuman_server::storage::AppState;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    tracing::info!("OpenHuman Server starting...");

    let backend = std::env::var("OPENHUMAN_BACKEND").unwrap_or_else(|_| "memory".to_string());

    let state = match backend.as_str() {
        "postgres" | "postgresql" | "pg" => {
            let db_url = std::env::var("DATABASE_URL").unwrap_or_else(|_| {
                "postgres://openhuman:openhuman@localhost:5432/openhuman".to_string()
            });
            tracing::info!("Using PostgreSQL backend: {}", db_url);
            let store = PostgresStore::new(&db_url).await?;
            store.migrate().await?;
            let reply = InMemoryReplyRegistry::new();
            AppState::from_postgres(store, reply)
        }
        _ => {
            tracing::info!("Using in-memory backend");
            let store = MemoryStore::seeded();
            AppState::from_store(store)
        }
    };

    let app = build_router(state);

    let host = std::env::var("OPENHUMAN_HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port: u16 = std::env::var("OPENHUMAN_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);

    tracing::info!("Listening on http://{}:{}", host, port);
    tracing::info!("WebSocket endpoint: ws://{}:{}/ws", host, port);
    tracing::info!("Demo API Key: ohk_demo_alice_codex");
    tracing::info!("  (pre-registered test identity — use this key in your AI tool's API config)");

    let listener = tokio::net::TcpListener::bind((host.as_str(), port)).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
