-- OpenHuman — Initial Schema Migration
-- Based on: protocol/examples/02-internal-storage.md
--
-- Tables:
--   identities                  (human identities)
--   agent_identities            (agent identities)
--   api_keys                    (keys binding agents ↔ humans)
--   conversations               (conversation metadata)
--   conversation_participants   (per-conversation participant refs)
--   messages                    (all messages, role-neutral)

-- ── Extensions ──

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- for uuid_generate_v4() fallback
CREATE EXTENSION IF NOT EXISTS "pgcrypto";    -- for digest() hashing
-- UUIDv7 is generated in Rust (uuid crate); we use TEXT columns with app-side
-- prefix conventions (hum_, agt_, key_, cnv_, msg_) for all IDs.

-- ── 1. Human Identities ──

CREATE TABLE IF NOT EXISTS identities (
    id            TEXT         PRIMARY KEY,
    display_name  TEXT         NOT NULL,
    avatar_url    TEXT,
    -- status is realtime (Redis); stored here as a fallback default
    status        TEXT         NOT NULL DEFAULT 'offline'
                              CHECK (status IN ('online', 'away', 'offline')),
    capabilities  JSONB        NOT NULL DEFAULT '[]'::jsonb,
    metadata      JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── 2. Agent Identities ──

CREATE TABLE IF NOT EXISTS agent_identities (
    id            TEXT         PRIMARY KEY,
    name          TEXT         NOT NULL,
    client_type   TEXT         NOT NULL
                              CHECK (client_type IN ('codex', 'claude_code', 'trae', 'custom')),
    api_key_id    TEXT         NOT NULL,
    capabilities  JSONB        NOT NULL DEFAULT '[]'::jsonb,
    metadata      JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_api_key ON agent_identities (api_key_id);

-- ── 3. API Keys ──
--
-- Only the SHA-256 digest is stored — never the raw plaintext.
-- Authentication resolves a key by hashing the inbound value and matching
-- `key_hash`, so a database compromise does not hand over live credentials.
--
-- A plain (unsalted) digest is deliberate: lookups are exact-match, so a
-- per-install salt would invalidate every previously issued key. API keys
-- are high-entropy random strings and are not exposed to the rainbow-table
-- weakness that unsalted *password* hashes suffer from.
--
-- Note: a `raw_key` plaintext column used to live here. It was removed by
-- migration 003, which backfills digests from it before dropping it.

CREATE TABLE IF NOT EXISTS api_keys (
    id            TEXT         PRIMARY KEY,
    key_hash      TEXT         NOT NULL,   -- SHA-256 hex of raw key
    agent_id      TEXT         NOT NULL REFERENCES agent_identities(id) ON DELETE CASCADE,
    human_id      TEXT         NOT NULL REFERENCES identities(id) ON DELETE CASCADE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_api_key_hash ON api_keys (key_hash);
CREATE INDEX IF NOT EXISTS idx_api_key_agent ON api_keys (agent_id);
CREATE INDEX IF NOT EXISTS idx_api_key_human ON api_keys (human_id);

-- ── 4. Conversations ──

CREATE TABLE IF NOT EXISTS conversations (
    id              TEXT         PRIMARY KEY,
    type            TEXT         NOT NULL
                                 CHECK (type IN ('agent_human', 'human_human')),
    title           TEXT,
    status          TEXT         NOT NULL DEFAULT 'active'
                                 CHECK (status IN ('created', 'active', 'archived', 'closed')),
    metadata        JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_conversation_status ON conversations (status);

-- ── 5. Conversation Participants ──
--
-- A separate table — conversations × participants is a many-to-many.
-- Composite key (conversation_id, participant_id) ensures uniqueness.

CREATE TABLE IF NOT EXISTS conversation_participants (
    conversation_id  TEXT         NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    participant_id   TEXT         NOT NULL,
    participant_type TEXT         NOT NULL
                                    CHECK (participant_type IN ('human', 'agent')),
    joined_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    role             TEXT         CHECK (role IN ('initiator', 'responder', 'observer')),

    PRIMARY KEY (conversation_id, participant_id)
);

CREATE INDEX IF NOT EXISTS idx_cp_participant ON conversation_participants (participant_id);
CREATE INDEX IF NOT EXISTS idx_cp_type ON conversation_participants (participant_type);

-- ── 6. Messages ──
--
-- content is JSONB: { "type": "text"|"structured"|"multipart", ... }
-- This matches the internal model's ContentBlock exactly.

CREATE TABLE IF NOT EXISTS messages (
    id              TEXT         PRIMARY KEY,
    conversation_id TEXT         NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       TEXT         NOT NULL,
    sender_type     TEXT         NOT NULL
                                 CHECK (sender_type IN ('human', 'agent')),
    content         JSONB        NOT NULL,
    attachments     JSONB        NOT NULL DEFAULT '[]'::jsonb,
    metadata        JSONB        NOT NULL DEFAULT '{}'::jsonb,
    status          TEXT         NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'sent', 'delivered', 'read', 'failed')),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_msg_conversation ON messages (conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_msg_sender ON messages (sender_id, sender_type);
CREATE INDEX IF NOT EXISTS idx_msg_status ON messages (status);

-- ── 7. Seed Data ──
-- Matches MemoryStore::seeded() exactly.

INSERT INTO identities (id, display_name, avatar_url, status, capabilities, metadata, created_at, updated_at)
VALUES (
    'hum_demo_alice',
    'Alice Chen',
    NULL,
    'online',
    '["answer_questions","review_design","provide_feedback"]'::jsonb,
    '{"timezone":"Asia/Shanghai","title":"Senior Engineer"}'::jsonb,
    NOW(),
    NOW()
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO agent_identities (id, name, client_type, api_key_id, capabilities, metadata, created_at, updated_at)
VALUES (
    'agt_demo_codex',
    'Codex Workspace',
    'codex',
    'key_demo_001',
    '["coding","analysis"]'::jsonb,
    '{}'::jsonb,
    NOW(),
    NOW()
)
ON CONFLICT (id) DO NOTHING;

-- Digest only. The plaintext demo key appears nowhere in the schema — it is
-- a well-known development credential, and its digest matches
-- `crypto::tests::seeded_demo_key_resolves`.
INSERT INTO api_keys (id, key_hash, agent_id, human_id, created_at)
VALUES (
    'key_demo_001',
    -- SHA-256 of "ohk_demo_alice_codex"
    encode(digest('ohk_demo_alice_codex', 'sha256'), 'hex'),
    'agt_demo_codex',
    'hum_demo_alice',
    NOW()
)
ON CONFLICT (id) DO NOTHING;
