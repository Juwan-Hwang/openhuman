//! PostgreSQL implementation of all repository traits (except ReplyRegistry).
//!
//! Phase 5A: Persistent storage backed by SQLx + PostgreSQL.
//! Phase 7: Agent capability + context persistence.
//!
//! `PostgresStore` implements `IdentityRepository`, `ConversationRepository`,
//! `MessageRepository`, `CapabilityRepository`, and `ContextRepository`.
//! The `ReplyRegistry` trait is implemented by the in-memory `InMemoryReplyRegistry`
//! — because reply channels carry live `mpsc::Sender` objects that are inherently
//! ephemeral and cannot be persisted to a database.
//!
//! # Architecture
//!
//! ```text
//!   AppState
//!     ├── identity:    Arc<dyn IdentityRepository>       ← PostgresStore
//!     ├── conversation: Arc<dyn ConversationRepository>  ← PostgresStore
//!     ├── message:     Arc<dyn MessageRepository>        ← PostgresStore
//!     ├── capability:  Arc<dyn CapabilityRepository>     ← PostgresStore
//!     ├── context:     Arc<dyn ContextRepository>        ← PostgresStore
//!     └── reply:       Arc<dyn ReplyRegistry>           ← InMemoryReplyRegistry
//! ```

use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use tokio::sync::mpsc;
use tokio::sync::Mutex;
use uuid::Uuid;

use sqlx::postgres::PgPool;
use sqlx::Executor;
use sqlx::Row;

use crate::model::agent_capability::AgentCapability;
use crate::model::agent_context::AgentContext;
use crate::model::content::ContentBlock;
use crate::model::conversation::{
    Conversation, ConversationParticipant, ConversationStatus, ConversationType, ParticipantRole,
};
use crate::model::identity::{
    AgentIdentity, ApiKey, ClientType, HumanIdentity, HumanStatus, ParticipantRef, ParticipantType,
};
use crate::model::message::{Message, MessageStatus};
use crate::state::AuthPrincipal;
use crate::storage::traits::{
    CapabilityRepository, ContextRepository, ConversationRepository, IdentityRepository,
    MessageRepository, ReplyRegistry,
};

// ════════════════════════════════════════════════════════════
//  PostgresStore
// ════════════════════════════════════════════════════════════

/// PostgreSQL-backed store implementing identity, conversation, and message
/// repository traits.
///
/// Cloning is cheap (inner `Arc<PgPool>`).
#[derive(Clone)]
pub struct PostgresStore {
    pool: Arc<PgPool>,
}

impl PostgresStore {
    /// Connect to a PostgreSQL database and return a `PostgresStore`.
    ///
    /// The connection string should be a standard PostgreSQL URL:
    /// `postgresql://user:password@host:5432/dbname`
    pub async fn new(database_url: &str) -> anyhow::Result<Self> {
        let pool = PgPool::connect(database_url).await?;
        Ok(Self {
            pool: Arc::new(pool),
        })
    }

    /// Create a `PostgresStore` from an existing `PgPool` (useful in tests).
    pub fn from_pool(pool: PgPool) -> Self {
        Self {
            pool: Arc::new(pool),
        }
    }

    /// Run all migration SQL files to create tables and seed data.
    ///
    /// Executes migrations in order: 001_init -> 002_capabilities ->
    /// 003_api_key_hashing -> 004_conversation_trash -> 005_tool_call_lookup.
    /// This is a simple `execute` of SQL file contents
    /// — not a full migration framework, but sufficient for Phase 5-7.
    ///
    /// All files are written to be re-runnable, so this is safe to
    /// call on every boot.
    pub async fn migrate(&self) -> anyhow::Result<()> {
        // Concurrent boots (or parallel tests) raced the migrations and
        // died on `CREATE EXTENSION`'s unique index. Take a session-wide
        // advisory lock inside one transaction: xact-scoped, so it always
        // releases on commit or rollback.
        let mut tx = self.pool.begin().await?;
        sqlx::query("SELECT pg_advisory_xact_lock(727001)")
            .execute(&mut *tx)
            .await?;
        let sql1 = include_str!("../../migrations/001_init.sql");
        tx.execute(sql1).await?;
        let sql2 = include_str!("../../migrations/002_capabilities.sql");
        tx.execute(sql2).await?;
        // 003 backfills real SHA-256 digests and drops the plaintext
        // `raw_key` column. It must run last — it reads `raw_key` in order
        // to derive the digests it replaces it with.
        let sql3 = include_str!("../../migrations/003_api_key_hashing.sql");
        tx.execute(sql3).await?;
        let sql4 = include_str!("../../migrations/004_conversation_trash.sql");
        tx.execute(sql4).await?;
        let sql5 = include_str!("../../migrations/005_tool_call_lookup.sql");
        tx.execute(sql5).await?;
        let sql6 = include_str!("../../migrations/006_key_scope.sql");
        tx.execute(sql6).await?;
        // 007 opens group rooms (type/role CHECKs, room_seq, counters,
        // invites, cursors, key binding). Re-runnable like the rest; the
        // rollback is 007_groups_down.sql, run by hand only.
        let sql7 = include_str!("../../migrations/007_groups.sql");
        tx.execute(sql7).await?;
        // 008 opens API task cards (the tasks table). Re-runnable like the
        // rest; the rollback is 008_task_cards_down.sql, run by hand only.
        let sql8 = include_str!("../../migrations/008_task_cards.sql");
        tx.execute(sql8).await?;
        // 009 persists the Files API. Rollback: 009_files_down.sql by hand.
        let sql9 = include_str!("../../migrations/009_files.sql");
        tx.execute(sql9).await?;
        // 010 persists OpenAI-style API objects (vector stores,
        // assistants/threads/runs, agents/sessions).
        // Rollback: 010_api_objects_down.sql by hand.
        let sql10 = include_str!("../../migrations/010_api_objects.sql");
        tx.execute(sql10).await?;
        // 001 re-seeds the public demo key on every boot. Outside an
        // explicit demo it must not authenticate anything.
        if std::env::var("OPENHUMAN_DEMO").ok().as_deref() != Some("1") {
            tx.execute("UPDATE api_keys SET scope = 'revoked' WHERE id = 'key_demo_001'")
                .await?;
        } else {
            tracing::warn!("OPENHUMAN_DEMO=1 — the public demo key is live");
        }
        tx.commit().await?;
        Ok(())
    }

    /// Expose the pool (for tests or advanced usage).
    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}

// ── IdentityRepository ──

#[async_trait]
impl IdentityRepository for PostgresStore {
    /// Resolve an API key to its principal, looked up **by SHA-256 digest**.
    ///
    /// The digest is computed from the inbound key and matched against
    /// `api_keys.key_hash`. The plaintext key never touches a query, and
    /// (after migration `003`) no plaintext column exists to leak.
    ///
    /// The returned `ApiKey.key` carries the raw key for the duration of
    /// this request only — see `ApiKey::persisted` for the form that is
    /// allowed to reach storage.
    async fn resolve_principal(&self, raw_key: &str) -> Option<AuthPrincipal> {
        let key_hash = api_key_hash(raw_key);

        let key_row = sqlx::query(
            "SELECT id, agent_id, human_id, scope, room_id FROM api_keys WHERE key_hash = $1",
        )
        .bind(&key_hash)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        let key_id: String = key_row.try_get("id").ok()?;
        let agent_id: String = key_row.try_get("agent_id").ok()?;
        let human_id: String = key_row.try_get("human_id").ok()?;
        let scope: String = key_row
            .try_get("scope")
            .unwrap_or_else(|_| "both".to_string());
        let room_id: Option<String> = key_row.try_get("room_id").ok().flatten();

        let agent = self.get_agent_inner(&agent_id).await?;
        let human = self.get_human_inner(&human_id).await?;

        Some(AuthPrincipal {
            agent,
            human,
            api_key: ApiKey {
                id: key_id,
                key: raw_key.to_string(),
                key_hash: Some(key_hash),
                agent_id,
                human_id,
                scope: crate::model::identity::KeyScope::parse(&scope),
                room_id,
            },
        })
    }

    async fn rename_agent(
        &self,
        agent_id: &str,
        human_id: &str,
        api_key_id: &str,
        name: &str,
    ) -> Option<AgentIdentity> {
        // The presented key must be the one this agent was issued under.
        // Matching on `(agent, human)` alone is too loose: two agents can
        // share a human, and then either key could rename the other.
        let result = sqlx::query(
            "UPDATE agent_identities AS a \
             SET name = $1, updated_at = now() \
             FROM api_keys k \
             WHERE a.id = $2 AND k.id = $3 AND k.agent_id = a.id \
               AND k.human_id = $4",
        )
        .bind(name)
        .bind(agent_id)
        .bind(api_key_id)
        .bind(human_id)
        .execute(&*self.pool)
        .await;

        let affected = match &result {
            Ok(r) => r.rows_affected(),
            Err(_) => 0,
        };
        tracing::info!(
            "rename_agent: agent={agent_id} human={human_id} name={name} \
             rows_affected={affected} err={:?}",
            result.as_ref().err()
        );

        match result {
            Ok(r) if r.rows_affected() > 0 => {
                let agent = self.get_agent(agent_id).await;
                tracing::info!("rename_agent: read back = {:?}", agent.is_some());
                agent
            }
            _ => None,
        }
    }

    async fn insert_human(&self, human: HumanIdentity) {
        let _ = sqlx::query(
            r#"
            INSERT INTO identities (id, display_name, avatar_url, status, capabilities, metadata, created_at, updated_at)
            VALUES ($1, $2, $3, 'online', $4, $5, $6, $7)
            ON CONFLICT (id) DO UPDATE SET
                display_name = EXCLUDED.display_name,
                avatar_url   = EXCLUDED.avatar_url,
                capabilities = EXCLUDED.capabilities,
                metadata     = EXCLUDED.metadata,
                updated_at   = EXCLUDED.updated_at
            "#,
        )
        .bind(&human.id)
        .bind(&human.display_name)
        .bind(&human.avatar_url)
        .bind(serde_json::to_value(&human.capabilities).unwrap_or_default())
        .bind(serde_json::to_value(&human.metadata).unwrap_or_default())
        .bind(human.created_at)
        .bind(human.updated_at)
        .execute(&*self.pool)
        .await;
    }

    async fn insert_agent(&self, agent: AgentIdentity) {
        let client_type_str = match agent.client_type {
            ClientType::Codex => "codex",
            ClientType::ClaudeCode => "claude_code",
            ClientType::Trae => "trae",
            ClientType::Custom => "custom",
        };

        let _ = sqlx::query(
            r#"
            INSERT INTO agent_identities (id, name, client_type, api_key_id, capabilities, metadata, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (id) DO UPDATE SET
                name         = EXCLUDED.name,
                client_type  = EXCLUDED.client_type,
                capabilities = EXCLUDED.capabilities,
                metadata     = EXCLUDED.metadata,
                updated_at   = EXCLUDED.updated_at
            "#,
        )
        .bind(&agent.id)
        .bind(&agent.name)
        .bind(client_type_str)
        .bind(&agent.api_key_id)
        .bind(serde_json::to_value(&agent.capabilities).unwrap_or_default())
        .bind(serde_json::to_value(&agent.metadata).unwrap_or_default())
        .bind(agent.created_at)
        .bind(agent.updated_at)
        .execute(&*self.pool)
        .await;
    }

    /// Store an API key — **digest only.**
    ///
    /// The plaintext is stripped via `ApiKey::persisted` before binding, and
    /// the `raw_key` column is not referenced at all. Migration `003` drops
    /// that column outright.
    ///
    /// If the caller hands over a record whose `key_hash` is absent (a legacy
    /// in-memory record), the digest is derived from the raw key here, so a
    /// plaintext value still never reaches the database.
    async fn insert_api_key(&self, key: ApiKey) {
        let key_hash = key
            .key_hash
            .clone()
            .filter(|h| !h.is_empty())
            .unwrap_or_else(|| api_key_hash(&key.key));

        let _ = sqlx::query(
            r#"
            INSERT INTO api_keys (id, key_hash, agent_id, human_id, scope, room_id, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, NOW())
            ON CONFLICT (id) DO UPDATE SET
                key_hash = EXCLUDED.key_hash,
                agent_id = EXCLUDED.agent_id,
                human_id = EXCLUDED.human_id,
                scope = EXCLUDED.scope,
                room_id = EXCLUDED.room_id
            "#,
        )
        .bind(&key.id)
        .bind(&key_hash)
        .bind(&key.agent_id)
        .bind(&key.human_id)
        .bind(key.scope.as_str())
        .bind(&key.room_id)
        .execute(&*self.pool)
        .await;
    }

    async fn api_key_scope(&self, id: &str) -> Option<crate::model::identity::KeyScope> {
        let row = sqlx::query("SELECT scope FROM api_keys WHERE id = $1")
            .bind(id)
            .fetch_optional(&*self.pool)
            .await
            .ok()??;
        let scope: String = row.try_get("scope").ok()?;
        Some(crate::model::identity::KeyScope::parse(&scope))
    }

    async fn get_human(&self, id: &str) -> Option<HumanIdentity> {
        self.get_human_inner(id).await
    }

    async fn get_agent(&self, id: &str) -> Option<AgentIdentity> {
        let row = sqlx::query(
            "SELECT id, name, client_type, api_key_id, capabilities, metadata, created_at, updated_at \
             FROM agent_identities WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        let client_type_str: String = row.try_get("client_type").ok()?;
        let caps_json: serde_json::Value = row.try_get("capabilities").ok()?;
        let meta_json: serde_json::Value = row.try_get("metadata").ok()?;

        Some(AgentIdentity {
            id: row.try_get("id").ok()?,
            name: row.try_get("name").ok()?,
            client_type: match client_type_str.as_str() {
                "codex" => ClientType::Codex,
                "claude_code" => ClientType::ClaudeCode,
                "trae" => ClientType::Trae,
                _ => ClientType::Custom,
            },
            api_key_id: row.try_get("api_key_id").ok()?,
            capabilities: serde_json::from_value(caps_json).unwrap_or_default(),
            metadata: serde_json::from_value(meta_json).unwrap_or_default(),
            created_at: row.try_get("created_at").ok()?,
            updated_at: row.try_get("updated_at").ok()?,
        })
    }

    async fn set_human_status(&self, id: &str, status: HumanStatus) -> bool {
        let status_str = match status {
            HumanStatus::Online => "online",
            HumanStatus::Away => "away",
            HumanStatus::Offline => "offline",
        };
        let result =
            sqlx::query("UPDATE identities SET status = $1, updated_at = now() WHERE id = $2")
                .bind(status_str)
                .bind(id)
                .execute(&*self.pool)
                .await;
        matches!(result, Ok(r) if r.rows_affected() > 0)
    }
}

/// Parse the `conversations.type` column.
fn parse_conversation_type(s: &str) -> ConversationType {
    match s {
        "human_human" => ConversationType::HumanHuman,
        "group" => ConversationType::Group,
        _ => ConversationType::AgentHuman,
    }
}

/// Parse the `conversation_participants.role` column.
fn parse_participant_role(s: &str) -> Option<ParticipantRole> {
    match s {
        "initiator" => Some(ParticipantRole::Initiator),
        "responder" => Some(ParticipantRole::Responder),
        "observer" => Some(ParticipantRole::Observer),
        "owner" => Some(ParticipantRole::Owner),
        "member" => Some(ParticipantRole::Member),
        _ => None,
    }
}

impl PostgresStore {
    /// Internal: fetch a human identity by ID.
    async fn get_human_inner(&self, id: &str) -> Option<HumanIdentity> {
        let row = sqlx::query(
            "SELECT id, display_name, avatar_url, status, capabilities, metadata, created_at, updated_at \
             FROM identities WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        let status_str: String = row.try_get("status").ok()?;
        let caps_json: serde_json::Value = row.try_get("capabilities").ok()?;
        let meta_json: serde_json::Value = row.try_get("metadata").ok()?;

        Some(HumanIdentity {
            id: row.try_get("id").ok()?,
            display_name: row.try_get("display_name").ok()?,
            avatar_url: row.try_get("avatar_url").ok()?,
            status: parse_human_status(&status_str),
            capabilities: serde_json::from_value(caps_json).unwrap_or_default(),
            metadata: serde_json::from_value(meta_json).unwrap_or_default(),
            created_at: row.try_get("created_at").ok()?,
            updated_at: row.try_get("updated_at").ok()?,
        })
    }

    /// Internal: fetch an agent identity by ID.
    async fn get_agent_inner(&self, id: &str) -> Option<AgentIdentity> {
        let row = sqlx::query(
            "SELECT id, name, client_type, api_key_id, capabilities, metadata, created_at, updated_at \
             FROM agent_identities WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        let ct_str: String = row.try_get("client_type").ok()?;
        let caps_json: serde_json::Value = row.try_get("capabilities").ok()?;
        let meta_json: serde_json::Value = row.try_get("metadata").ok()?;

        Some(AgentIdentity {
            id: row.try_get("id").ok()?,
            name: row.try_get("name").ok()?,
            client_type: parse_client_type(&ct_str),
            api_key_id: row.try_get("api_key_id").ok()?,
            capabilities: serde_json::from_value(caps_json).unwrap_or_default(),
            metadata: serde_json::from_value(meta_json).unwrap_or_default(),
            created_at: row.try_get("created_at").ok()?,
            updated_at: row.try_get("updated_at").ok()?,
        })
    }
}

// ── ConversationRepository ──

#[async_trait]
impl ConversationRepository for PostgresStore {
    async fn find_or_create(
        &self,
        agent_id: &str,
        human_id: &str,
        session_key: &str,
        system_prompt: Option<String>,
    ) -> Conversation {
        // All three dimensions participate in the lookup: agent + human +
        // session. The previous implementation matched on agent alone, which
        // collapsed every chat window (and, in multi-human setups, every
        // human) onto one shared transcript.
        let existing = self
            .find_conversation_scoped(agent_id, human_id, session_key)
            .await;
        if let Some(cnv) = existing {
            return cnv;
        }

        // Create a new conversation.
        let now = Utc::now();
        let conversation_id = format!("cnv_{}", Uuid::now_v7().simple());

        // Build metadata with optional system_prompt — plus the session key,
        // which is how this conversation is matched on subsequent requests.
        let metadata: serde_json::Value = {
            let mut m = serde_json::Map::new();
            if let Some(prompt) = system_prompt {
                m.insert(
                    "system_prompt".to_string(),
                    serde_json::Value::String(prompt),
                );
            }
            m.insert(
                "session_key".to_string(),
                serde_json::Value::String(session_key.to_string()),
            );
            serde_json::Value::Object(m)
        };

        // Insert conversation.
        let _ = sqlx::query(
            r#"
            INSERT INTO conversations (id, type, title, status, metadata, created_at, updated_at, last_message_at)
            VALUES ($1, 'agent_human', NULL, 'active', $2, $3, $4, NULL)
            "#,
        )
        .bind(&conversation_id)
        .bind(&metadata)
        .bind(now)
        .bind(now)
        .execute(&*self.pool)
        .await;

        // Insert participants.
        let _ = sqlx::query(
            r#"
            INSERT INTO conversation_participants (conversation_id, participant_id, participant_type, joined_at, role)
            VALUES ($1, $2, 'agent', $3, 'initiator')
            "#,
        )
        .bind(&conversation_id)
        .bind(agent_id)
        .bind(now)
        .execute(&*self.pool)
        .await;

        let _ = sqlx::query(
            r#"
            INSERT INTO conversation_participants (conversation_id, participant_id, participant_type, joined_at, role)
            VALUES ($1, $2, 'human', $3, 'responder')
            "#,
        )
        .bind(&conversation_id)
        .bind(human_id)
        .bind(now)
        .execute(&*self.pool)
        .await;

        // Return the conversation object.
        Conversation {
            id: conversation_id,
            conversation_type: ConversationType::AgentHuman,
            participants: vec![
                ConversationParticipant {
                    participant: ParticipantRef::agent(agent_id),
                    joined_at: now,
                    role: Some(ParticipantRole::Initiator),
                    first_visible_seq: None,
                },
                ConversationParticipant {
                    participant: ParticipantRef::human(human_id),
                    joined_at: now,
                    role: Some(ParticipantRole::Responder),
                    first_visible_seq: None,
                },
            ],
            title: None,
            status: ConversationStatus::Active,
            metadata: {
                let mut m = HashMap::new();
                if let serde_json::Value::Object(map) = &metadata {
                    for (k, v) in map {
                        m.insert(k.clone(), v.clone());
                    }
                }
                m
            },
            created_at: now,
            updated_at: now,
            last_message_at: None,
            deleted_at: None,
        }
    }

    async fn get(&self, id: &str) -> Option<Conversation> {
        let row = sqlx::query(
            "SELECT id, type, title, status, metadata, created_at, updated_at, last_message_at \
             FROM conversations WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        let conversation_id: String = row.try_get("id").ok()?;
        let participants = self.get_participants(&conversation_id).await;
        let type_str: String = row.try_get("type").unwrap_or_default();

        Some(Conversation {
            id: conversation_id,
            conversation_type: parse_conversation_type(&type_str),
            participants,
            title: row.try_get("title").ok()?,
            status: ConversationStatus::Active,
            deleted_at: row.try_get("deleted_at").ok().flatten(),
            metadata: {
                let v: serde_json::Value = row.try_get("metadata").ok()?;
                serde_json::from_value(v).unwrap_or_default()
            },
            created_at: row.try_get("created_at").ok()?,
            updated_at: row.try_get("updated_at").ok()?,
            last_message_at: row.try_get("last_message_at").ok()?,
        })
    }

    async fn get_by_agent(&self, agent_id: &str) -> Option<Conversation> {
        self.find_conversation_by_agent(agent_id).await
    }

    async fn list_for_human(&self, human_id: &str) -> Vec<Conversation> {
        // Find all conversation IDs where this human is a participant.
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT c.id, c.type, c.title, c.status, c.metadata, c.created_at, c.updated_at, c.last_message_at
            FROM conversations c
            JOIN conversation_participants cp ON cp.conversation_id = c.id
            WHERE cp.participant_id = $1 AND cp.participant_type = 'human'
              AND c.deleted_at IS NULL
            ORDER BY c.last_message_at DESC NULLS LAST
            "#,
        )
        .bind(human_id)
        .fetch_all(&*self.pool)
        .await;

        let rows = match rows {
            Ok(r) => r,
            Err(_) => return Vec::new(),
        };

        let mut conversations = Vec::new();
        for row in &rows {
            if let Ok(conversation_id) = row.try_get::<String, _>("id") {
                let participants = self.get_participants(&conversation_id).await;
                let type_str: String = row.try_get("type").unwrap_or_default();
                conversations.push(Conversation {
                    id: conversation_id,
                    conversation_type: parse_conversation_type(&type_str),
                    participants,
                    title: row.try_get("title").ok(),
                    status: ConversationStatus::Active,
                    metadata: {
                        let v: serde_json::Value = row.try_get("metadata").unwrap_or_default();
                        serde_json::from_value(v).unwrap_or_default()
                    },
                    created_at: row.try_get("created_at").unwrap_or_else(|_| Utc::now()),
                    updated_at: row.try_get("updated_at").unwrap_or_else(|_| Utc::now()),
                    last_message_at: row.try_get("last_message_at").ok(),
                    deleted_at: row.try_get("deleted_at").ok().flatten(),
                });
            }
        }

        conversations
    }

    async fn soft_delete(&self, id: &str) -> bool {
        let result = sqlx::query(
            "UPDATE conversations SET deleted_at = now(), updated_at = now() \
             WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(id)
        .execute(&*self.pool)
        .await;

        matches!(result, Ok(r) if r.rows_affected() > 0)
    }

    async fn restore(&self, id: &str) -> bool {
        let result = sqlx::query(
            "UPDATE conversations SET deleted_at = NULL, updated_at = now() \
             WHERE id = $1 AND deleted_at IS NOT NULL",
        )
        .bind(id)
        .execute(&*self.pool)
        .await;

        matches!(result, Ok(r) if r.rows_affected() > 0)
    }

    async fn delete_permanent(&self, id: &str) -> bool {
        // Only ever reached from the trash. Children go first: participants
        // and messages reference the conversation, so removing the parent
        // row while they remain would leave the rest dangling.
        let _ = sqlx::query("DELETE FROM messages WHERE conversation_id = $1")
            .bind(id)
            .execute(&*self.pool)
            .await;
        let _ = sqlx::query("DELETE FROM conversation_participants WHERE conversation_id = $1")
            .bind(id)
            .execute(&*self.pool)
            .await;

        let result = sqlx::query("DELETE FROM conversations WHERE id = $1")
            .bind(id)
            .execute(&*self.pool)
            .await;

        matches!(result, Ok(r) if r.rows_affected() > 0)
    }

    async fn list_deleted_for_human(&self, human_id: &str) -> Vec<Conversation> {
        // `deleted_at` is selected because DISTINCT requires ORDER BY
        // expressions to appear in the select list — leaving it out makes
        // Postgres reject the query outright, which silently returned an
        // empty trash.
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT c.id, c.type, c.title, c.status, c.metadata, c.created_at,
                            c.updated_at, c.last_message_at, c.deleted_at
            FROM conversations c
            JOIN conversation_participants cp ON cp.conversation_id = c.id
            WHERE cp.participant_id = $1 AND cp.participant_type = 'human'
              AND c.deleted_at IS NOT NULL
            ORDER BY c.deleted_at DESC
            "#,
        )
        .bind(human_id)
        .fetch_all(&*self.pool)
        .await;

        let rows = match rows {
            Ok(r) => r,
            Err(e) => {
                tracing::error!("list_deleted_for_human failed: {e}");
                return Vec::new();
            }
        };

        let mut conversations = Vec::new();
        for row in &rows {
            if let Ok(conversation_id) = row.try_get::<String, _>("id") {
                let participants = self.get_participants(&conversation_id).await;
                let type_str: String = row.try_get("type").unwrap_or_default();
                conversations.push(Conversation {
                    id: conversation_id,
                    conversation_type: parse_conversation_type(&type_str),
                    participants,
                    title: row.try_get("title").ok(),
                    status: ConversationStatus::Active,
                    metadata: {
                        let v: serde_json::Value = row.try_get("metadata").unwrap_or_default();
                        serde_json::from_value(v).unwrap_or_default()
                    },
                    created_at: row.try_get("created_at").unwrap_or_else(|_| Utc::now()),
                    updated_at: row.try_get("updated_at").unwrap_or_else(|_| Utc::now()),
                    last_message_at: row.try_get("last_message_at").ok(),
                    deleted_at: row.try_get("deleted_at").ok().flatten(),
                });
            }
        }

        conversations
    }
}

impl PostgresStore {
    /// Internal: find the conversation scoped to `(agent, human, session_key)`.
    ///
    /// Requires BOTH participants to match — the previous
    /// `find_conversation_by_agent` matched on the agent alone, so one API
    /// key produced exactly one conversation no matter which human or which
    /// chat window was talking.
    ///
    /// `session_key` is matched against `metadata->>'session_key'`. Rows
    /// written before that dimension existed hold `NULL` and therefore never
    /// match, so legacy transcripts stay intact and untouched instead of
    /// silently absorbing new traffic.
    async fn find_conversation_scoped(
        &self,
        agent_id: &str,
        human_id: &str,
        session_key: &str,
    ) -> Option<Conversation> {
        let row = sqlx::query(
            r#"
            SELECT c.id, c.type, c.title, c.status, c.metadata, c.created_at, c.updated_at, c.last_message_at
            FROM conversations c
            JOIN conversation_participants cpa
              ON cpa.conversation_id = c.id
             AND cpa.participant_type = 'agent'
             AND cpa.participant_id = $1
            JOIN conversation_participants cph
              ON cph.conversation_id = c.id
             AND cph.participant_type = 'human'
             AND cph.participant_id = $2
            WHERE c.metadata->>'session_key' = $3
            ORDER BY c.created_at DESC
            LIMIT 1
            "#,
        )
        .bind(agent_id)
        .bind(human_id)
        .bind(session_key)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        let conversation_id: String = row.try_get("id").ok()?;
        let participants = self.get_participants(&conversation_id).await;
        let type_str: String = row.try_get("type").unwrap_or_default();

        Some(Conversation {
            id: conversation_id,
            conversation_type: parse_conversation_type(&type_str),
            participants,
            title: row.try_get("title").ok()?,
            status: ConversationStatus::Active,
            deleted_at: row.try_get("deleted_at").ok().flatten(),
            metadata: {
                let v: serde_json::Value = row.try_get("metadata").ok()?;
                serde_json::from_value(v).unwrap_or_default()
            },
            created_at: row.try_get("created_at").ok()?,
            updated_at: row.try_get("updated_at").ok()?,
            last_message_at: row.try_get("last_message_at").ok()?,
        })
    }

    /// Internal: find a conversation where the given agent is a participant.
    async fn find_conversation_by_agent(&self, agent_id: &str) -> Option<Conversation> {
        let row = sqlx::query(
            r#"
            SELECT c.id, c.type, c.title, c.status, c.metadata, c.created_at, c.updated_at, c.last_message_at
            FROM conversations c
            JOIN conversation_participants cp ON cp.conversation_id = c.id
            WHERE cp.participant_id = $1 AND cp.participant_type = 'agent'
            ORDER BY c.created_at DESC
            LIMIT 1
            "#,
        )
        .bind(agent_id)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        let conversation_id: String = row.try_get("id").ok()?;
        let participants = self.get_participants(&conversation_id).await;
        let type_str: String = row.try_get("type").unwrap_or_default();

        Some(Conversation {
            id: conversation_id,
            conversation_type: parse_conversation_type(&type_str),
            participants,
            title: row.try_get("title").ok()?,
            status: ConversationStatus::Active,
            deleted_at: row.try_get("deleted_at").ok().flatten(),
            metadata: {
                let v: serde_json::Value = row.try_get("metadata").ok()?;
                serde_json::from_value(v).unwrap_or_default()
            },
            created_at: row.try_get("created_at").ok()?,
            updated_at: row.try_get("updated_at").ok()?,
            last_message_at: row.try_get("last_message_at").ok()?,
        })
    }

    /// Internal: get all participants for a conversation.
    async fn get_participants(&self, conversation_id: &str) -> Vec<ConversationParticipant> {
        let rows = sqlx::query(
            "SELECT participant_id, participant_type, joined_at, role, first_visible_seq \
             FROM conversation_participants WHERE conversation_id = $1 ORDER BY joined_at",
        )
        .bind(conversation_id)
        .fetch_all(&*self.pool)
        .await
        .unwrap_or_default();

        rows.into_iter()
            .filter_map(|r| {
                let pid: String = r.try_get("participant_id").ok()?;
                let ptype_str: String = r.try_get("participant_type").ok()?;
                let joined_at: DateTime<Utc> = r.try_get("joined_at").ok()?;
                let role_str: Option<String> = r.try_get("role").ok()?;

                let participant_type = match ptype_str.as_str() {
                    "human" => ParticipantType::Human,
                    _ => ParticipantType::Agent,
                };

                let role = role_str.as_deref().and_then(parse_participant_role);
                let first_visible_seq: Option<i64> = r.try_get("first_visible_seq").ok().flatten();

                Some(ConversationParticipant {
                    participant: ParticipantRef {
                        participant_id: pid,
                        participant_type,
                        display_name: None,
                    },
                    joined_at,
                    role,
                    first_visible_seq,
                })
            })
            .collect()
    }
}

// ── MessageRepository ──

#[async_trait]
impl MessageRepository for PostgresStore {
    async fn insert(&self, message: Message) {
        let content_json = serde_json::to_value(&message.content).unwrap_or_default();
        let attachments_json = serde_json::to_value(&message.attachments).unwrap_or_default();
        let metadata_json = serde_json::to_value(&message.metadata).unwrap_or_default();
        let sender_type_str = match message.sender.participant_type {
            ParticipantType::Human => "human",
            ParticipantType::Agent => "agent",
        };

        let _ = sqlx::query(
            r#"
            INSERT INTO messages (id, conversation_id, sender_id, sender_type, sender_name, content, attachments, metadata, status, created_at, room_seq)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            ON CONFLICT (id) DO NOTHING
            "#,
        )
        .bind(&message.id)
        .bind(&message.conversation_id)
        .bind(&message.sender.participant_id)
        .bind(sender_type_str)
        .bind(&message.sender.display_name)
        .bind(&content_json)
        .bind(&attachments_json)
        .bind(&metadata_json)
        .bind(match message.status {
            MessageStatus::Pending => "pending",
            MessageStatus::Sent => "sent",
            MessageStatus::Delivered => "delivered",
            MessageStatus::Read => "read",
            MessageStatus::Failed => "failed",
        })
        .bind(message.created_at)
        .bind(message.room_seq)
        .execute(&*self.pool)
        .await;

        // Update last_message_at on the conversation.
        let _ = sqlx::query(
            "UPDATE conversations SET last_message_at = $1, updated_at = $1 WHERE id = $2",
        )
        .bind(message.created_at)
        .bind(&message.conversation_id)
        .execute(&*self.pool)
        .await;
    }

    async fn list(&self, conversation_id: &str) -> Vec<Message> {
        let rows = sqlx::query(
            "SELECT id, conversation_id, sender_id, sender_type, sender_name, content, attachments, metadata, status, created_at, room_seq \
             FROM messages WHERE conversation_id = $1 ORDER BY created_at ASC",
        )
        .bind(conversation_id)
        .fetch_all(&*self.pool)
        .await
        .unwrap_or_default();

        rows.into_iter()
            .filter_map(|r| {
                let id: String = r.try_get("id").ok()?;
                let cid: String = r.try_get("conversation_id").ok()?;
                let sender_id: String = r.try_get("sender_id").ok()?;
                let sender_type_str: String = r.try_get("sender_type").ok()?;
                let content_json: serde_json::Value = r.try_get("content").ok()?;
                let attachments_json: serde_json::Value = r.try_get("attachments").ok()?;
                let metadata_json: serde_json::Value = r.try_get("metadata").ok()?;
                let status_str: String = r.try_get("status").ok()?;
                let created_at: DateTime<Utc> = r.try_get("created_at").ok()?;

                let sender_type = match sender_type_str.as_str() {
                    "human" => ParticipantType::Human,
                    _ => ParticipantType::Agent,
                };

                let status = match status_str.as_str() {
                    "pending" => MessageStatus::Pending,
                    "sent" => MessageStatus::Sent,
                    "delivered" => MessageStatus::Delivered,
                    "read" => MessageStatus::Read,
                    _ => MessageStatus::Failed,
                };

                let content: ContentBlock =
                    serde_json::from_value(content_json).unwrap_or(ContentBlock::text(""));

                Some(Message {
                    id,
                    conversation_id: cid,
                    sender: ParticipantRef {
                        participant_id: sender_id,
                        participant_type: sender_type,
                        display_name: r.try_get("sender_name").ok().flatten(),
                    },
                    content,
                    attachments: serde_json::from_value(attachments_json).unwrap_or_default(),
                    metadata: serde_json::from_value(metadata_json).unwrap_or_default(),
                    status,
                    visibility: crate::model::message::MessageVisibility::HumanVisible,
                    created_at,
                    room_seq: r.try_get("room_seq").ok().flatten(),
                })
            })
            .collect()
    }

    async fn list_undelivered(&self, human_id: &str) -> Vec<Message> {
        // Participants live in `conversation_participants` — there is no
        // `human_id` column on `conversations`. The query that assumed one
        // failed on every call, and the failure was swallowed, so the
        // backlog was never drained and messages stayed `pending` forever.
        let rows = sqlx::query(
            r#"
            SELECT m.id, m.conversation_id, m.sender_id, m.sender_type, m.sender_name, m.content,
                   m.attachments, m.metadata, m.status, m.created_at, m.room_seq
            FROM messages m
            JOIN conversation_participants cp
              ON cp.conversation_id = m.conversation_id
            WHERE cp.participant_id = $1
              AND cp.participant_type = 'human'
              AND m.status = 'pending'
              AND m.sender_id <> $1
            ORDER BY m.created_at ASC
            "#,
        )
        .bind(human_id)
        .fetch_all(&*self.pool)
        .await;

        let rows = match rows {
            Ok(r) => r,
            Err(e) => {
                // Never `unwrap_or_default` here: an empty backlog and a
                // failed lookup look identical to the caller, and the
                // latter means messages silently never arrive.
                tracing::error!("list_undelivered failed for {human_id}: {e}");
                return Vec::new();
            }
        };

        rows.into_iter()
            .filter_map(|r| {
                let id: String = r.try_get("id").ok()?;
                let cid: String = r.try_get("conversation_id").ok()?;
                let sender_id: String = r.try_get("sender_id").ok()?;
                let sender_type_str: String = r.try_get("sender_type").ok()?;
                let content_json: serde_json::Value = r.try_get("content").ok()?;
                let attachments_json: serde_json::Value = r.try_get("attachments").ok()?;
                let metadata_json: serde_json::Value = r.try_get("metadata").ok()?;
                let created_at: DateTime<Utc> = r.try_get("created_at").ok()?;

                let sender_type = match sender_type_str.as_str() {
                    "human" => ParticipantType::Human,
                    _ => ParticipantType::Agent,
                };
                let content: ContentBlock =
                    serde_json::from_value(content_json).unwrap_or(ContentBlock::text(""));

                Some(Message {
                    id,
                    conversation_id: cid,
                    sender: ParticipantRef {
                        participant_id: sender_id,
                        participant_type: sender_type,
                        display_name: r.try_get("sender_name").ok().flatten(),
                    },
                    content,
                    attachments: serde_json::from_value(attachments_json).unwrap_or_default(),
                    metadata: serde_json::from_value(metadata_json).unwrap_or_default(),
                    status: MessageStatus::Pending,
                    visibility: crate::model::message::MessageVisibility::HumanVisible,
                    created_at,
                    room_seq: r.try_get("room_seq").ok().flatten(),
                })
            })
            .collect()
    }

    async fn mark_delivered(&self, message_ids: &[String]) {
        if message_ids.is_empty() {
            return;
        }
        // Only flip messages that are still pending: later statuses (read,
        // failed) carry information this must not overwrite.
        let _ = sqlx::query(
            "UPDATE messages SET status = 'delivered' WHERE id = ANY($1) AND status = 'pending'",
        )
        .bind(message_ids)
        .execute(&*self.pool)
        .await;
    }

    async fn find_tool_call(&self, conversation_id: &str, tool_call_id: &str) -> Option<Message> {
        // Direct lookup on the metadata index — the previous implementation
        // loaded the whole conversation and scanned it in Rust, which gets
        // slower with every message in the thread.
        let row = sqlx::query(
            "SELECT id, conversation_id, sender_id, sender_type, sender_name, content, attachments, metadata, status, created_at, room_seq \
             FROM messages \
             WHERE conversation_id = $1 \
               AND metadata->>'tool_call_id' = $2 \
               AND metadata ? 'tool_id' \
             ORDER BY created_at DESC LIMIT 1",
        )
        .bind(conversation_id)
        .bind(tool_call_id)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        let sender_type_str: String = row.try_get("sender_type").ok()?;
        let content_json: serde_json::Value = row.try_get("content").ok()?;
        let attachments_json: serde_json::Value = row.try_get("attachments").ok()?;
        let metadata_json: serde_json::Value = row.try_get("metadata").ok()?;
        let status_str: String = row.try_get("status").ok()?;

        Some(Message {
            id: row.try_get("id").ok()?,
            conversation_id: row.try_get("conversation_id").ok()?,
            sender: ParticipantRef {
                participant_id: row.try_get("sender_id").ok()?,
                participant_type: match sender_type_str.as_str() {
                    "human" => ParticipantType::Human,
                    _ => ParticipantType::Agent,
                },
                display_name: row.try_get("sender_name").ok().flatten(),
            },
            content: serde_json::from_value(content_json).unwrap_or(ContentBlock::text("")),
            attachments: serde_json::from_value(attachments_json).unwrap_or_default(),
            metadata: serde_json::from_value(metadata_json).unwrap_or_default(),
            status: match status_str.as_str() {
                "pending" => MessageStatus::Pending,
                "sent" => MessageStatus::Sent,
                "delivered" => MessageStatus::Delivered,
                "read" => MessageStatus::Read,
                _ => MessageStatus::Failed,
            },
            visibility: crate::model::message::MessageVisibility::HumanVisible,
            created_at: row.try_get("created_at").ok()?,
            room_seq: row.try_get("room_seq").ok().flatten(),
        })
    }
}

// ── CapabilityRepository (Phase 7) ──

#[async_trait]
impl CapabilityRepository for PostgresStore {
    async fn set_capabilities(&self, agent_id: &str, capabilities: Vec<AgentCapability>) {
        // Delete existing capabilities, then insert new ones (upsert manifest).
        let _ = sqlx::query("DELETE FROM agent_capabilities WHERE agent_id = $1")
            .bind(agent_id)
            .execute(&*self.pool)
            .await;

        for cap in &capabilities {
            let _ = sqlx::query(
                r#"
                INSERT INTO agent_capabilities
                    (agent_id, id, name, description, category,
                     input_schema, output_schema, ui_schema,
                     permissions, metadata, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
                ON CONFLICT (agent_id, id) DO UPDATE SET
                    name          = EXCLUDED.name,
                    description   = EXCLUDED.description,
                    category      = EXCLUDED.category,
                    input_schema  = EXCLUDED.input_schema,
                    output_schema = EXCLUDED.output_schema,
                    ui_schema     = EXCLUDED.ui_schema,
                    permissions   = EXCLUDED.permissions,
                    metadata      = EXCLUDED.metadata,
                    updated_at    = NOW()
                "#,
            )
            .bind(agent_id)
            .bind(&cap.id)
            .bind(&cap.name)
            .bind(&cap.description)
            .bind(&cap.category)
            .bind(&cap.input_schema)
            .bind(&cap.output_schema)
            .bind(&cap.ui_schema)
            .bind(serde_json::to_value(&cap.permissions).unwrap_or_default())
            .bind(serde_json::to_value(&cap.metadata).unwrap_or_default())
            .execute(&*self.pool)
            .await;
        }
    }

    async fn get_capabilities(&self, agent_id: &str) -> Vec<AgentCapability> {
        let rows = sqlx::query(
            "SELECT id, name, description, category, input_schema, output_schema, \
             ui_schema, permissions, metadata \
             FROM agent_capabilities WHERE agent_id = $1 ORDER BY id",
        )
        .bind(agent_id)
        .fetch_all(&*self.pool)
        .await
        .unwrap_or_default();

        rows.into_iter()
            .filter_map(|r| {
                let perms_json: serde_json::Value = r.try_get("permissions").ok()?;
                let meta_json: serde_json::Value = r.try_get("metadata").ok()?;
                Some(AgentCapability {
                    id: r.try_get("id").ok()?,
                    name: r.try_get("name").ok()?,
                    description: r.try_get("description").ok()?,
                    category: r.try_get("category").ok()?,
                    input_schema: r.try_get("input_schema").ok()?,
                    output_schema: r.try_get("output_schema").ok()?,
                    ui_schema: r.try_get("ui_schema").ok()?,
                    permissions: serde_json::from_value(perms_json).unwrap_or_default(),
                    metadata: serde_json::from_value(meta_json).unwrap_or_default(),
                })
            })
            .collect()
    }

    async fn get_capability(&self, agent_id: &str, tool_id: &str) -> Option<AgentCapability> {
        let row = sqlx::query(
            "SELECT id, name, description, category, input_schema, output_schema, \
             ui_schema, permissions, metadata \
             FROM agent_capabilities WHERE agent_id = $1 AND id = $2",
        )
        .bind(agent_id)
        .bind(tool_id)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        let perms_json: serde_json::Value = row.try_get("permissions").ok()?;
        let meta_json: serde_json::Value = row.try_get("metadata").ok()?;
        Some(AgentCapability {
            id: row.try_get("id").ok()?,
            name: row.try_get("name").ok()?,
            description: row.try_get("description").ok()?,
            category: row.try_get("category").ok()?,
            input_schema: row.try_get("input_schema").ok()?,
            output_schema: row.try_get("output_schema").ok()?,
            ui_schema: row.try_get("ui_schema").ok()?,
            permissions: serde_json::from_value(perms_json).unwrap_or_default(),
            metadata: serde_json::from_value(meta_json).unwrap_or_default(),
        })
    }

    async fn clear_capabilities(&self, agent_id: &str) {
        let _ = sqlx::query("DELETE FROM agent_capabilities WHERE agent_id = $1")
            .bind(agent_id)
            .execute(&*self.pool)
            .await;
    }
}

// ── ContextRepository (Phase 7) ──

#[async_trait]
impl ContextRepository for PostgresStore {
    async fn set_context(&self, agent_id: &str, context: AgentContext) {
        let _ = sqlx::query(
            r#"
            INSERT INTO agent_contexts
                (agent_id, system_prompt, model, runtime, environment, updated_at)
            VALUES ($1, $2, $3, $4, $5, NOW())
            ON CONFLICT (agent_id) DO UPDATE SET
                system_prompt = EXCLUDED.system_prompt,
                model         = EXCLUDED.model,
                runtime       = EXCLUDED.runtime,
                environment   = EXCLUDED.environment,
                updated_at    = NOW()
            "#,
        )
        .bind(agent_id)
        .bind(&context.system_prompt)
        .bind(&context.model)
        .bind(&context.runtime)
        .bind(&context.environment)
        .execute(&*self.pool)
        .await;
    }

    async fn get_context(&self, agent_id: &str) -> Option<AgentContext> {
        let row = sqlx::query(
            "SELECT agent_id, system_prompt, model, runtime, environment \
             FROM agent_contexts WHERE agent_id = $1",
        )
        .bind(agent_id)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;

        Some(AgentContext {
            agent_id: row.try_get("agent_id").ok()?,
            system_prompt: row.try_get("system_prompt").ok()?,
            model: row.try_get("model").ok()?,
            runtime: row.try_get("runtime").ok()?,
            environment: row.try_get("environment").ok()?,
        })
    }
}

// ════════════════════════════════════════════════════════════
//  InMemoryReplyRegistry
// ════════════════════════════════════════════════════════════

/// Ephemeral in-memory reply channel registry.
///
/// This is always in-memory because it carries live `mpsc::Sender` objects
/// that cannot be serialized to a database. Even with PostgreSQL persistence,
/// the reply bridge between SSE and WebSocket is inherently ephemeral.
#[derive(Default)]
struct ReplyData {
    pending: HashMap<String, Vec<mpsc::UnboundedSender<String>>>,
}

/// Thread-safe in-memory reply registry (Clone is cheap — inner `Arc`).
#[derive(Clone)]
pub struct InMemoryReplyRegistry {
    data: Arc<Mutex<ReplyData>>,
}

impl InMemoryReplyRegistry {
    pub fn new() -> Self {
        Self {
            data: Arc::new(Mutex::new(ReplyData::default())),
        }
    }
}

impl Default for InMemoryReplyRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl ReplyRegistry for InMemoryReplyRegistry {
    async fn register(&self, conversation_id: &str, tx: mpsc::UnboundedSender<String>) {
        let mut data = self.data.lock().await;
        // The newest request on a conversation supersedes any older one: an
        // older one still open is a caller that resubmitted (a retry, or a
        // proxy replaying the request). Dropping its sender ends that
        // handler quietly instead of refusing the new request with 409.
        data.pending.insert(conversation_id.to_string(), vec![tx]);
    }

    async fn remove(&self, conversation_id: &str) {
        let mut data = self.data.lock().await;
        // A superseded handler sees its channel closed and exits without
        // calling this, so removing everything here only ends the turn
        // that actually finished.
        data.pending.remove(conversation_id);
    }

    async fn deliver(&self, conversation_id: &str, text: &str) -> bool {
        let mut data = self.data.lock().await;
        if let Some(channels) = data.pending.get_mut(conversation_id) {
            // Drop channels whose request already went away (client
            // disconnected mid-stream), then deliver to the newest live one.
            channels.retain(|tx| !tx.is_closed());
            if let Some(tx) = channels.last() {
                let _ = tx.send(text.to_string());
                return true;
            }
        }
        false
    }

    async fn conversations_with_waiters(&self) -> Vec<String> {
        let data = self.data.lock().await;
        data.pending
            .iter()
            .filter(|(_, channels)| channels.iter().any(|tx| !tx.is_closed()))
            .map(|(id, _)| id.clone())
            .collect()
    }
}

// ════════════════════════════════════════════════════════════
//  Helpers
// ════════════════════════════════════════════════════════════

/// SHA-256 hex digest of an API key — the persisted, indexed form.
///
/// Previously a `DefaultHasher` placeholder lived here. It was 64-bit,
/// non-cryptographic, and **not stable across process restarts**, so it
/// could not serve as a lookup key at all — authentication silently fell
/// back to `WHERE raw_key = $1`. See `crate::crypto` for the rationale.
///
/// A plain (unsalted) digest is deliberate: lookups are exact-match, so a
/// per-install salt would invalidate every issued key on migration. API
/// keys are high-entropy random strings, so they are not exposed to the
/// rainbow-table weakness that unsalted password hashes suffer from.
fn api_key_hash(raw_key: &str) -> String {
    crate::crypto::sha256_hex(raw_key)
}

/// Parse a human status string from the DB.
fn parse_human_status(s: &str) -> Option<HumanStatus> {
    match s {
        "online" => Some(HumanStatus::Online),
        "away" => Some(HumanStatus::Away),
        "offline" => Some(HumanStatus::Offline),
        _ => None,
    }
}

/// Parse a client type string from the DB.
fn parse_client_type(s: &str) -> ClientType {
    match s {
        "codex" => ClientType::Codex,
        "claude_code" => ClientType::ClaudeCode,
        "trae" => ClientType::Trae,
        _ => ClientType::Custom,
    }
}

// ── RoomRepository (migration 007) ──

use crate::storage::traits::{RoomInvite, RoomRepository};

/// Map a messages row into the model — shared by the room log reads.
fn message_from_row(r: &sqlx::postgres::PgRow) -> Option<Message> {
    let sender_type_str: String = r.try_get("sender_type").ok()?;
    let content_json: serde_json::Value = r.try_get("content").ok()?;
    let status_str: String = r.try_get("status").ok()?;
    Some(Message {
        id: r.try_get("id").ok()?,
        conversation_id: r.try_get("conversation_id").ok()?,
        sender: ParticipantRef {
            participant_id: r.try_get("sender_id").ok()?,
            participant_type: match sender_type_str.as_str() {
                "human" => ParticipantType::Human,
                _ => ParticipantType::Agent,
            },
            display_name: r.try_get("sender_name").ok().flatten(),
        },
        content: serde_json::from_value(content_json).unwrap_or(ContentBlock::text("")),
        attachments: serde_json::from_value(r.try_get("attachments").ok()?).unwrap_or_default(),
        metadata: serde_json::from_value(r.try_get("metadata").ok()?).unwrap_or_default(),
        status: match status_str.as_str() {
            "pending" => MessageStatus::Pending,
            "sent" => MessageStatus::Sent,
            "delivered" => MessageStatus::Delivered,
            "read" => MessageStatus::Read,
            _ => MessageStatus::Failed,
        },
        visibility: crate::model::message::MessageVisibility::HumanVisible,
        created_at: r.try_get("created_at").ok()?,
        room_seq: r.try_get("room_seq").ok().flatten(),
    })
}

#[async_trait]
impl RoomRepository for PostgresStore {
    async fn room_create(
        &self,
        room_id: &str,
        title: &str,
        owner: &ParticipantRef,
    ) -> Conversation {
        let now = Utc::now();
        let _ = sqlx::query(
            "INSERT INTO conversations (id, type, title, status, metadata, created_at, updated_at) \
             VALUES ($1, 'group', $2, 'active', '{}'::jsonb, $3, $3)",
        )
        .bind(room_id)
        .bind(title)
        .bind(now)
        .execute(&*self.pool)
        .await;
        let _ = sqlx::query(
            "INSERT INTO conversation_participants \
             (conversation_id, participant_id, participant_type, joined_at, role, first_visible_seq) \
             VALUES ($1, $2, $3, $4, 'owner', NULL)",
        )
        .bind(room_id)
        .bind(&owner.participant_id)
        .bind(match owner.participant_type {
            ParticipantType::Human => "human",
            ParticipantType::Agent => "agent",
        })
        .bind(now)
        .execute(&*self.pool)
        .await;
        let _ = sqlx::query(
            "INSERT INTO room_counters (room_id, next_seq) VALUES ($1, 1) \
             ON CONFLICT (room_id) DO NOTHING",
        )
        .bind(room_id)
        .execute(&*self.pool)
        .await;
        self.get(room_id).await.unwrap_or_else(|| Conversation {
            id: room_id.to_string(),
            conversation_type: ConversationType::Group,
            participants: vec![ConversationParticipant {
                participant: owner.clone(),
                joined_at: now,
                role: Some(ParticipantRole::Owner),
                first_visible_seq: None,
            }],
            title: Some(title.to_string()),
            status: ConversationStatus::Active,
            metadata: HashMap::new(),
            created_at: now,
            updated_at: now,
            last_message_at: None,
            deleted_at: None,
        })
    }

    async fn room_append(&self, mut message: Message) -> Option<Message> {
        // Sequence allocation and insert commit in one transaction: two
        // concurrent appends must never share a number, and a broadcast
        // must never precede the commit that makes it durable.
        let mut tx = self.pool.begin().await.ok()?;
        let row = sqlx::query(
            "INSERT INTO room_counters (room_id, next_seq) VALUES ($1, 2) \
             ON CONFLICT (room_id) DO UPDATE SET next_seq = room_counters.next_seq + 1 \
             RETURNING next_seq",
        )
        .bind(&message.conversation_id)
        .fetch_one(&mut *tx)
        .await
        .ok()?;
        let seq: i64 = row.try_get::<i64, _>("next_seq").ok()? - 1;
        message.room_seq = Some(seq);

        let content_json = serde_json::to_value(&message.content).unwrap_or_default();
        let attachments_json = serde_json::to_value(&message.attachments).unwrap_or_default();
        let metadata_json = serde_json::to_value(&message.metadata).unwrap_or_default();
        sqlx::query(
            "INSERT INTO messages \
             (id, conversation_id, sender_id, sender_type, sender_name, content, attachments, metadata, status, created_at, room_seq) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        )
        .bind(&message.id)
        .bind(&message.conversation_id)
        .bind(&message.sender.participant_id)
        .bind(match message.sender.participant_type {
            ParticipantType::Human => "human",
            ParticipantType::Agent => "agent",
        })
        .bind(&message.sender.display_name)
        .bind(&content_json)
        .bind(&attachments_json)
        .bind(&metadata_json)
        .bind("sent")
        .bind(message.created_at)
        .bind(seq)
        .execute(&mut *tx)
        .await
        .ok()?;
        let _ = sqlx::query(
            "UPDATE conversations SET last_message_at = $1, updated_at = $1 WHERE id = $2",
        )
        .bind(message.created_at)
        .bind(&message.conversation_id)
        .execute(&mut *tx)
        .await;
        tx.commit().await.ok()?;
        Some(message)
    }

    async fn room_next_seq(&self, room_id: &str) -> i64 {
        sqlx::query("SELECT next_seq FROM room_counters WHERE room_id = $1")
            .bind(room_id)
            .fetch_optional(&*self.pool)
            .await
            .ok()
            .flatten()
            .and_then(|r| r.try_get("next_seq").ok())
            .unwrap_or(1)
    }

    async fn room_messages_since(
        &self,
        room_id: &str,
        after_seq: i64,
        min_seq: i64,
        limit: usize,
    ) -> Vec<Message> {
        let rows = sqlx::query(
            "SELECT id, conversation_id, sender_id, sender_type, sender_name, content, attachments, metadata, status, created_at, room_seq \
             FROM messages \
             WHERE conversation_id = $1 AND room_seq IS NOT NULL AND room_seq > $2 AND room_seq >= $3 \
             ORDER BY room_seq ASC LIMIT $4",
        )
        .bind(room_id)
        .bind(after_seq)
        .bind(min_seq)
        .bind(limit as i64)
        .fetch_all(&*self.pool)
        .await
        .unwrap_or_default();
        rows.iter().filter_map(message_from_row).collect()
    }

    async fn room_add_member(
        &self,
        room_id: &str,
        participant: &ParticipantRef,
        role: ParticipantRole,
        first_visible_seq: Option<i64>,
    ) -> bool {
        let role_str = match role {
            ParticipantRole::Owner => "owner",
            ParticipantRole::Member => "member",
            ParticipantRole::Initiator => "initiator",
            ParticipantRole::Responder => "responder",
            ParticipantRole::Observer => "observer",
        };
        let result = sqlx::query(
            "INSERT INTO conversation_participants \
             (conversation_id, participant_id, participant_type, joined_at, role, first_visible_seq) \
             VALUES ($1, $2, $3, NOW(), $4, $5) \
             ON CONFLICT (conversation_id, participant_id) DO UPDATE \
             SET role = EXCLUDED.role, first_visible_seq = EXCLUDED.first_visible_seq",
        )
        .bind(room_id)
        .bind(&participant.participant_id)
        .bind(match participant.participant_type {
            ParticipantType::Human => "human",
            ParticipantType::Agent => "agent",
        })
        .bind(role_str)
        .bind(first_visible_seq)
        .execute(&*self.pool)
        .await;
        matches!(result, Ok(r) if r.rows_affected() > 0)
    }

    async fn room_remove_member(&self, room_id: &str, participant_id: &str) -> bool {
        let result = sqlx::query(
            "DELETE FROM conversation_participants \
             WHERE conversation_id = $1 AND participant_id = $2 AND role <> 'owner'",
        )
        .bind(room_id)
        .bind(participant_id)
        .execute(&*self.pool)
        .await;
        matches!(result, Ok(r) if r.rows_affected() > 0)
    }

    async fn room_member_role(
        &self,
        room_id: &str,
        participant_id: &str,
    ) -> Option<ParticipantRole> {
        let row = sqlx::query(
            "SELECT role FROM conversation_participants \
             WHERE conversation_id = $1 AND participant_id = $2",
        )
        .bind(room_id)
        .bind(participant_id)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;
        let role: Option<String> = row.try_get("role").ok()?;
        role.as_deref().and_then(parse_participant_role)
    }

    async fn room_first_visible_seq(&self, room_id: &str, participant_id: &str) -> Option<i64> {
        sqlx::query(
            "SELECT first_visible_seq FROM conversation_participants \
             WHERE conversation_id = $1 AND participant_id = $2",
        )
        .bind(room_id)
        .bind(participant_id)
        .fetch_optional(&*self.pool)
        .await
        .ok()
        .flatten()
        .and_then(|r| {
            r.try_get::<Option<i64>, _>("first_visible_seq")
                .ok()
                .flatten()
        })
    }

    async fn room_update_metadata(&self, room_id: &str, patch: serde_json::Value) -> bool {
        let result = sqlx::query(
            "UPDATE conversations SET metadata = metadata || $2::jsonb, updated_at = NOW() \
             WHERE id = $1 AND type = 'group'",
        )
        .bind(room_id)
        .bind(&patch)
        .execute(&*self.pool)
        .await;
        matches!(result, Ok(r) if r.rows_affected() > 0)
    }

    async fn room_invite_create(&self, invite: RoomInvite) -> bool {
        let result = sqlx::query(
            "INSERT INTO room_invites (code_hash, room_id, created_by, created_at, expires_at) \
             VALUES ($1, $2, $3, $4, $5) ON CONFLICT (code_hash) DO NOTHING",
        )
        .bind(&invite.code_hash)
        .bind(&invite.room_id)
        .bind(&invite.created_by)
        .bind(invite.created_at)
        .bind(invite.expires_at)
        .execute(&*self.pool)
        .await;
        matches!(result, Ok(r) if r.rows_affected() > 0)
    }

    async fn room_invite_get(&self, code_hash: &str) -> Option<RoomInvite> {
        let row = sqlx::query(
            "SELECT code_hash, room_id, created_by, created_at, expires_at, revoked_at \
             FROM room_invites WHERE code_hash = $1",
        )
        .bind(code_hash)
        .fetch_optional(&*self.pool)
        .await
        .ok()??;
        Some(RoomInvite {
            code_hash: row.try_get("code_hash").ok()?,
            room_id: row.try_get("room_id").ok()?,
            created_by: row.try_get("created_by").ok()?,
            created_at: row.try_get("created_at").ok()?,
            expires_at: row.try_get("expires_at").ok()?,
            revoked_at: row.try_get("revoked_at").ok()?,
        })
    }

    async fn room_invite_revoke(&self, room_id: &str, code_hash: &str) -> bool {
        let result = sqlx::query(
            "UPDATE room_invites SET revoked_at = NOW() \
             WHERE room_id = $1 AND code_hash = $2 AND revoked_at IS NULL",
        )
        .bind(room_id)
        .bind(code_hash)
        .execute(&*self.pool)
        .await;
        matches!(result, Ok(r) if r.rows_affected() > 0)
    }

    async fn room_cursor_get(
        &self,
        room_id: &str,
        api_key_id: &str,
        session_key: &str,
    ) -> Option<i64> {
        sqlx::query(
            "SELECT last_received_seq FROM room_caller_cursors \
             WHERE room_id = $1 AND api_key_id = $2 AND session_key = $3",
        )
        .bind(room_id)
        .bind(api_key_id)
        .bind(session_key)
        .fetch_optional(&*self.pool)
        .await
        .ok()
        .flatten()
        .and_then(|r| r.try_get("last_received_seq").ok())
    }

    async fn room_cursor_set(
        &self,
        room_id: &str,
        api_key_id: &str,
        session_key: &str,
        last_received_seq: i64,
    ) {
        let _ = sqlx::query(
            "INSERT INTO room_caller_cursors (room_id, api_key_id, session_key, last_received_seq) \
             VALUES ($1, $2, $3, $4) \
             ON CONFLICT (room_id, api_key_id, session_key) \
             DO UPDATE SET last_received_seq = EXCLUDED.last_received_seq",
        )
        .bind(room_id)
        .bind(api_key_id)
        .bind(session_key)
        .bind(last_received_seq)
        .execute(&*self.pool)
        .await;
    }

    async fn room_revoke_keys(&self, room_id: &str) {
        // Revoke AND unbind: the row stays for audit, but the api_keys →
        // conversations FK is NO ACTION, so a still-bound key would block
        // deleting the room (silently — delete_permanent swallows it).
        let _ =
            sqlx::query("UPDATE api_keys SET scope = 'revoked', room_id = NULL WHERE room_id = $1")
                .bind(room_id)
                .execute(&*self.pool)
                .await;
    }

    async fn room_member_count(&self, room_id: &str) -> usize {
        sqlx::query(
            "SELECT COUNT(*) AS n FROM conversation_participants WHERE conversation_id = $1",
        )
        .bind(room_id)
        .fetch_one(&*self.pool)
        .await
        .ok()
        .and_then(|r| r.try_get::<i64, _>("n").ok())
        .unwrap_or(0) as usize
    }
}

// ── Task Repository (postgres) ──

fn tasks_max_per_owner() -> i64 {
    std::env::var("OPENHUMAN_TASKS_MAX_PER_OWNER")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(2_000)
}

fn tasks_max_total() -> i64 {
    std::env::var("OPENHUMAN_TASKS_MAX_TOTAL")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(20_000)
}

fn task_from_row(r: &sqlx::postgres::PgRow) -> crate::model::task::TaskRecord {
    use sqlx::Row;
    let status: String = r.get("status");
    let created: chrono::DateTime<chrono::Utc> = r.get("created_at");
    let updated: chrono::DateTime<chrono::Utc> = r.get("updated_at");
    crate::model::task::TaskRecord {
        id: r.get("id"),
        owner: r.get("owner"),
        api: r.get("api"),
        status: crate::model::task::TaskStatus::parse(&status)
            .unwrap_or(crate::model::task::TaskStatus::Failed),
        conversation_id: r.get("conversation_id"),
        request: r.get("request"),
        answer: r.get("answer"),
        error: r.get("error"),
        created_at: created.timestamp(),
        updated_at: updated.timestamp(),
    }
}

const TASK_COLS: &str =
    "id, owner, api, status, conversation_id, request, answer, error, created_at, updated_at";

#[async_trait::async_trait]
impl crate::storage::traits::TaskRepository for PostgresStore {
    async fn create_task(&self, task: crate::model::task::TaskRecord) {
        let _ = sqlx::query(
            "INSERT INTO tasks (id, owner, api, status, conversation_id, request, answer, error)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
             ON CONFLICT (id) DO NOTHING",
        )
        .bind(&task.id)
        .bind(&task.owner)
        .bind(&task.api)
        .bind(task.status.as_str())
        .bind(&task.conversation_id)
        .bind(&task.request)
        .bind(&task.answer)
        .bind(&task.error)
        .execute(&*self.pool)
        .await;
        // Quota pruning: only finished rows are ever removed, oldest first;
        // active work is untouchable even when the cap is exceeded.
        let _ = sqlx::query(
            "DELETE FROM tasks WHERE id IN (
                 SELECT id FROM tasks
                 WHERE owner = $1 AND status IN ('completed', 'failed')
                 ORDER BY created_at DESC OFFSET $2)",
        )
        .bind(&task.owner)
        .bind(tasks_max_per_owner())
        .execute(&*self.pool)
        .await;
        let _ = sqlx::query(
            "DELETE FROM tasks WHERE id IN (
                 SELECT id FROM tasks
                 WHERE status IN ('completed', 'failed')
                 ORDER BY created_at DESC OFFSET $1)",
        )
        .bind(tasks_max_total())
        .execute(&*self.pool)
        .await;
    }

    async fn bind_task_conversation(&self, id: &str, conversation_id: &str) {
        let _ =
            sqlx::query("UPDATE tasks SET conversation_id = $2, updated_at = now() WHERE id = $1")
                .bind(id)
                .bind(conversation_id)
                .execute(&*self.pool)
                .await;
    }

    async fn finish_task(
        &self,
        id: &str,
        answer: Option<serde_json::Value>,
        error: Option<String>,
    ) {
        // Never reopen a finished task: a late duplicate answer loses.
        let status = if error.is_some() {
            "failed"
        } else {
            "completed"
        };
        let _ = sqlx::query(
            "UPDATE tasks SET status = $2, answer = $3, error = $4, updated_at = now()
             WHERE id = $1 AND status NOT IN ('completed', 'failed')",
        )
        .bind(id)
        .bind(status)
        .bind(&answer)
        .bind(&error)
        .execute(&*self.pool)
        .await;
    }

    async fn fail_in_flight_tasks(&self, reason: &str) -> u64 {
        sqlx::query(
            "UPDATE tasks SET status = 'failed', error = $1, updated_at = now()
             WHERE status IN ('queued', 'running')",
        )
        .bind(reason)
        .execute(&*self.pool)
        .await
        .map(|r| r.rows_affected())
        .unwrap_or(0)
    }

    async fn get_task(&self, owner: &str, id: &str) -> Option<crate::model::task::TaskRecord> {
        sqlx::query(&format!(
            "SELECT {TASK_COLS} FROM tasks WHERE id = $1 AND owner = $2"
        ))
        .bind(id)
        .bind(owner)
        .fetch_optional(&*self.pool)
        .await
        .ok()
        .flatten()
        .map(|r| task_from_row(&r))
    }

    async fn list_tasks(&self, owner: &str, limit: i64) -> Vec<crate::model::task::TaskRecord> {
        sqlx::query(&format!(
            "SELECT {TASK_COLS} FROM tasks WHERE owner = $1
             ORDER BY created_at DESC, id DESC LIMIT $2"
        ))
        .bind(owner)
        .bind(limit.max(0))
        .fetch_all(&*self.pool)
        .await
        .map(|rows| rows.iter().map(task_from_row).collect())
        .unwrap_or_default()
    }
}

// ── File Repository (postgres) ──

fn files_max_bytes_per_owner() -> i64 {
    std::env::var("OPENHUMAN_FILES_MAX_BYTES_PER_OWNER")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(512 * 1024 * 1024)
}

fn files_max_bytes_total() -> i64 {
    std::env::var("OPENHUMAN_FILES_MAX_BYTES_TOTAL")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(2 * 1024 * 1024 * 1024)
}

fn file_from_row(r: &sqlx::postgres::PgRow) -> crate::api::files::StoredFile {
    use sqlx::Row;
    let created: chrono::DateTime<chrono::Utc> = r.get("created_at");
    crate::api::files::StoredFile {
        owner: r.get("owner"),
        filename: r.get("filename"),
        mime: r.get("mime"),
        purpose: r.get("purpose"),
        bytes: r.get("bytes"),
        created_at: created.timestamp(),
    }
}

#[async_trait::async_trait]
impl crate::storage::traits::FileRepository for PostgresStore {
    async fn put_file(&self, id: &str, file: crate::api::files::StoredFile) {
        let id = id.to_string();
        let _ = sqlx::query(
            "INSERT INTO files (id, owner, filename, mime, purpose, bytes)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (id) DO NOTHING",
        )
        .bind(&id)
        .bind(&file.owner)
        .bind(&file.filename)
        .bind(&file.mime)
        .bind(&file.purpose)
        .bind(&file.bytes)
        .execute(&*self.pool)
        .await;
        // Byte quotas: a row whose running byte total (newest first)
        // exceeds the cap is old enough to go. Two steps, race-tolerable.
        let _ = sqlx::query(
            "DELETE FROM files f WHERE f.owner = $1 AND EXISTS (
                 SELECT 1 FROM (
                     SELECT id, SUM(octet_length(bytes)) OVER (ORDER BY created_at DESC, id DESC) AS running
                     FROM files WHERE owner = $1
                 ) s WHERE s.id = f.id AND s.running > $2)",
        )
        .bind(&file.owner)
        .bind(files_max_bytes_per_owner())
        .execute(&*self.pool)
        .await;
        let _ = sqlx::query(
            "DELETE FROM files f WHERE EXISTS (
                 SELECT 1 FROM (
                     SELECT id, SUM(octet_length(bytes)) OVER (ORDER BY created_at DESC, id DESC) AS running
                     FROM files
                 ) s WHERE s.id = f.id AND s.running > $1)",
        )
        .bind(files_max_bytes_total())
        .execute(&*self.pool)
        .await;
    }

    async fn get_file(&self, id: &str) -> Option<crate::api::files::StoredFile> {
        sqlx::query(
            "SELECT owner, filename, mime, purpose, bytes, created_at FROM files WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(&*self.pool)
        .await
        .ok()
        .flatten()
        .map(|r| file_from_row(&r))
    }

    async fn delete_file(&self, owner: &str, id: &str) -> bool {
        sqlx::query("DELETE FROM files WHERE id = $1 AND owner = $2")
            .bind(id)
            .bind(owner)
            .execute(&*self.pool)
            .await
            .map(|r| r.rows_affected() > 0)
            .unwrap_or(false)
    }

    async fn list_files(&self, owner: &str) -> Vec<(String, crate::api::files::StoredFile)> {
        use sqlx::Row;
        sqlx::query(
            "SELECT id, owner, filename, mime, purpose, bytes, created_at FROM files
             WHERE owner = $1 ORDER BY created_at DESC, id DESC",
        )
        .bind(owner)
        .fetch_all(&*self.pool)
        .await
        .map(|rows| {
            rows.iter()
                .map(|r| (r.get("id"), file_from_row(r)))
                .collect()
        })
        .unwrap_or_default()
    }

    async fn find_output_by_bytes(&self, bytes: &[u8]) -> Option<(String, i64)> {
        use sqlx::Row;
        sqlx::query(
            "SELECT id, created_at FROM files
             WHERE purpose = 'output' AND md5(bytes) = md5($1) AND bytes = $1
             ORDER BY created_at DESC LIMIT 1",
        )
        .bind(bytes)
        .fetch_optional(&*self.pool)
        .await
        .ok()
        .flatten()
        .map(|r| {
            let created: chrono::DateTime<chrono::Utc> = r.get("created_at");
            (r.get("id"), created.timestamp())
        })
    }
}

/// Per-owner cap on stored API objects of one kind;
/// `OPENHUMAN_API_OBJECTS_MAX_PER_OWNER` overrides (default 2000).
fn api_objects_max_per_owner() -> i64 {
    std::env::var("OPENHUMAN_API_OBJECTS_MAX_PER_OWNER")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(2000)
}

#[async_trait]
impl crate::storage::traits::ObjectRepository for PostgresStore {
    async fn put_object(&self, id: &str, owner: &str, obj: crate::storage::traits::StoredObject) {
        let kind = obj
            .obj
            .get("object")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let last_active = obj
            .obj
            .get("last_active_at")
            .or_else(|| obj.obj.get("created_at"))
            .and_then(|v| v.as_i64())
            .unwrap_or_else(|| Utc::now().timestamp());
        let _ = sqlx::query(
            "INSERT INTO api_objects (id, owner, object_kind, obj, input, history, last_active_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (id) DO UPDATE SET obj = $4, input = $5, history = $6, last_active_at = $7",
        )
        .bind(id)
        .bind(owner)
        .bind(&kind)
        .bind(&obj.obj)
        .bind(serde_json::Value::from(obj.input))
        .bind(serde_json::Value::from(obj.history))
        .bind(last_active)
        .execute(&*self.pool)
        .await;
        // Per-owner, per-kind cap: least recently active goes first.
        let _ = sqlx::query(
            "DELETE FROM api_objects v WHERE v.owner = $1 AND v.object_kind = $2 AND EXISTS (
                 SELECT 1 FROM (
                     SELECT id, ROW_NUMBER() OVER (ORDER BY last_active_at DESC, id DESC) AS rn
                     FROM api_objects WHERE owner = $1 AND object_kind = $2
                 ) s WHERE s.id = v.id AND s.rn > $3)",
        )
        .bind(owner)
        .bind(&kind)
        .bind(api_objects_max_per_owner())
        .execute(&*self.pool)
        .await;
    }

    async fn get_object(
        &self,
        owner: &str,
        id: &str,
    ) -> Option<crate::storage::traits::StoredObject> {
        sqlx::query("SELECT obj, input, history FROM api_objects WHERE id = $1 AND owner = $2")
            .bind(id)
            .bind(owner)
            .fetch_optional(&*self.pool)
            .await
            .ok()
            .flatten()
            .map(|r| crate::storage::traits::StoredObject {
                obj: r.get("obj"),
                input: r
                    .get::<serde_json::Value, _>("input")
                    .as_array()
                    .cloned()
                    .unwrap_or_default(),
                history: r
                    .get::<serde_json::Value, _>("history")
                    .as_array()
                    .cloned()
                    .unwrap_or_default(),
            })
    }

    async fn update_object(
        &self,
        id: &str,
        f: &(dyn for<'a> Fn(&'a mut crate::storage::traits::StoredObject) + Send + Sync),
    ) -> bool {
        // Read-modify-write in one transaction: the row lock keeps two
        // concurrent updates from losing each other.
        let mut tx = match self.pool.begin().await {
            Ok(t) => t,
            Err(_) => return false,
        };
        let row =
            sqlx::query("SELECT obj, input, history FROM api_objects WHERE id = $1 FOR UPDATE")
                .bind(id)
                .fetch_optional(&mut *tx)
                .await;
        let Ok(Some(r)) = row else {
            let _ = tx.rollback().await;
            return false;
        };
        let mut v = crate::storage::traits::StoredObject {
            obj: r.get("obj"),
            input: r
                .get::<serde_json::Value, _>("input")
                .as_array()
                .cloned()
                .unwrap_or_default(),
            history: r
                .get::<serde_json::Value, _>("history")
                .as_array()
                .cloned()
                .unwrap_or_default(),
        };
        f(&mut v);
        let last_active = v
            .obj
            .get("last_active_at")
            .or_else(|| v.obj.get("created_at"))
            .and_then(|x| x.as_i64())
            .unwrap_or_else(|| Utc::now().timestamp());
        let done = sqlx::query(
            "UPDATE api_objects SET obj = $2, input = $3, history = $4, last_active_at = $5 WHERE id = $1",
        )
        .bind(id)
        .bind(&v.obj)
        .bind(serde_json::Value::from(v.input))
        .bind(serde_json::Value::from(v.history))
        .bind(last_active)
        .execute(&mut *tx)
        .await;
        match done {
            Ok(_) => {
                let _ = tx.commit().await;
                true
            }
            Err(_) => {
                let _ = tx.rollback().await;
                false
            }
        }
    }

    async fn list_objects(
        &self,
        owner: &str,
        object_kind: &str,
    ) -> Vec<(String, crate::storage::traits::StoredObject)> {
        sqlx::query(
            "SELECT id, obj, input, history FROM api_objects
             WHERE owner = $1 AND object_kind = $2 ORDER BY last_active_at DESC, id DESC",
        )
        .bind(owner)
        .bind(object_kind)
        .fetch_all(&*self.pool)
        .await
        .map(|rows| {
            rows.iter()
                .map(|r| {
                    (
                        r.get("id"),
                        crate::storage::traits::StoredObject {
                            obj: r.get("obj"),
                            input: r
                                .get::<serde_json::Value, _>("input")
                                .as_array()
                                .cloned()
                                .unwrap_or_default(),
                            history: r
                                .get::<serde_json::Value, _>("history")
                                .as_array()
                                .cloned()
                                .unwrap_or_default(),
                        },
                    )
                })
                .collect()
        })
        .unwrap_or_default()
    }

    async fn delete_object(&self, owner: &str, id: &str) -> bool {
        sqlx::query("DELETE FROM api_objects WHERE id = $1 AND owner = $2")
            .bind(id)
            .bind(owner)
            .execute(&*self.pool)
            .await
            .map(|r| r.rows_affected() > 0)
            .unwrap_or(false)
    }
}
