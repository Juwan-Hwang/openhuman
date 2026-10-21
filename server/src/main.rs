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

    // Admin: `openhuman-server issue-key ...` mints a key and exits.
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(|s| s.as_str()) == Some("issue-key") {
        return issue_key(&args[2..]).await;
    }

    tracing::info!("OpenHuman Server starting...");

    let backend = std::env::var("OPENHUMAN_BACKEND").unwrap_or_else(|_| "memory".to_string());

    let state = match backend.as_str() {
        "postgres" | "postgresql" | "pg" => {
            let db_url = std::env::var("DATABASE_URL").unwrap_or_else(|_| {
                "postgres://openhuman:openhuman@localhost:5432/openhuman".to_string()
            });
            tracing::info!("Using PostgreSQL backend: {}", redact_db_url(&db_url));
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
    if backend == "memory" {
        tracing::info!("Demo API Key: ohk_demo_alice_codex");
        tracing::info!("  (in-memory dev identity — use this key in your AI tool's API config)");
    }

    let listener = tokio::net::TcpListener::bind((host.as_str(), port)).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

/// `postgres://user:secret@host/db` → `postgres://user:***@host/db`.
fn redact_db_url(url: &str) -> String {
    match (url.find("://"), url.rfind('@')) {
        (Some(scheme), Some(at)) if at > scheme => {
            let creds = &url[scheme + 3..at];
            match creds.find(':') {
                Some(colon) => format!(
                    "{}{}:***{}",
                    &url[..scheme + 3],
                    &creds[..colon],
                    &url[at..]
                ),
                None => url.to_string(),
            }
        }
        _ => url.to_string(),
    }
}

/// Mint an API key against the PostgreSQL store, creating the human and
/// agent identities when they do not exist yet. Prints the raw key once;
/// only its SHA-256 digest is stored.
///
/// ```text
/// openhuman-server issue-key --human hum_x --human-name "Hark" \
///     --agent agt_x --agent-name "Juwan's Claude Code" --scope caller
/// ```
async fn issue_key(args: &[String]) -> anyhow::Result<()> {
    use openhuman_server::model::identity::{
        AgentIdentity, ApiKey, ClientType, HumanIdentity, HumanStatus, KeyScope,
    };
    use openhuman_server::storage::traits::IdentityRepository;
    use std::collections::HashMap;

    let get = |flag: &str| -> Option<String> {
        args.iter()
            .position(|a| a == flag)
            .and_then(|i| args.get(i + 1).cloned())
    };
    let human_id = get("--human").ok_or_else(|| anyhow::anyhow!("--human <id> is required"))?;
    let agent_id = get("--agent").ok_or_else(|| anyhow::anyhow!("--agent <id> is required"))?;
    let scope = KeyScope::parse(&get("--scope").unwrap_or_else(|| "caller".into()));
    if scope == KeyScope::Revoked {
        anyhow::bail!("refusing to mint a revoked key");
    }

    let db_url = std::env::var("DATABASE_URL")
        .map_err(|_| anyhow::anyhow!("DATABASE_URL must be set for issue-key"))?;
    let store = PostgresStore::new(&db_url).await?;
    store.migrate().await?;
    let now = chrono::Utc::now();

    if store.get_human(&human_id).await.is_none() {
        store
            .insert_human(HumanIdentity {
                id: human_id.clone(),
                display_name: get("--human-name").unwrap_or_else(|| human_id.clone()),
                avatar_url: None,
                status: Some(HumanStatus::Offline),
                capabilities: Vec::new(),
                metadata: HashMap::new(),
                created_at: now,
                updated_at: now,
            })
            .await;
    }

    let key_id = format!("key_{}", uuid::Uuid::now_v7().simple());
    if store.get_agent(&agent_id).await.is_none() {
        store
            .insert_agent(AgentIdentity {
                id: agent_id.clone(),
                name: get("--agent-name").unwrap_or_else(|| agent_id.clone()),
                client_type: ClientType::Custom,
                api_key_id: key_id.clone(),
                capabilities: Vec::new(),
                metadata: HashMap::new(),
                created_at: now,
                updated_at: now,
            })
            .await;
    }

    let raw = format!(
        "ohk_{}{}",
        uuid::Uuid::new_v4().simple(),
        uuid::Uuid::new_v4().simple()
    );
    store
        .insert_api_key(ApiKey::new(&key_id, &raw, &agent_id, &human_id).with_scope(scope))
        .await;

    // Read it back so a silently failed insert is not reported as success.
    match store.resolve_principal(&raw).await {
        Some(p) if p.api_key.scope == scope => {
            println!("key_id={key_id}");
            println!("scope={}", scope.as_str());
            println!("human={human_id}");
            println!("agent={agent_id}");
            println!("api_key={raw}");
            Ok(())
        }
        _ => anyhow::bail!("key was not stored (check the human / agent ids)"),
    }
}
