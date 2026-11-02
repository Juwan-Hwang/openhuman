-- ═══════════════════════════════════════════════════════════
-- Migration 007 — group rooms
-- ═══════════════════════════════════════════════════════════
-- A room is a conversation with type 'group'. Members are ordinary rows in
-- conversation_participants with role 'owner' / 'member'. Everything here
-- is re-runnable; the rollback lives in 007_groups_down.sql.

-- 1) Allow group conversations.
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_type_check;
ALTER TABLE conversations ADD CONSTRAINT conversations_type_check
    CHECK (type IN ('agent_human', 'human_human', 'group'));

-- 2) Allow room roles.
ALTER TABLE conversation_participants DROP CONSTRAINT IF EXISTS conversation_participants_role_check;
ALTER TABLE conversation_participants ADD CONSTRAINT conversation_participants_role_check
    CHECK (role IN ('initiator', 'responder', 'observer', 'owner', 'member'));

-- 3) New-member visibility watermark: the first room_seq a member may see.
ALTER TABLE conversation_participants
    ADD COLUMN IF NOT EXISTS first_visible_seq BIGINT;

-- 4) Per-room monotone sequence on messages (NULL for non-room messages).
ALTER TABLE messages ADD COLUMN IF NOT EXISTS room_seq BIGINT;
CREATE INDEX IF NOT EXISTS idx_messages_room ON messages (conversation_id, room_seq)
    WHERE room_seq IS NOT NULL;

-- 5) Per-room sequence allocator (take numbers inside a transaction).
CREATE TABLE IF NOT EXISTS room_counters (
    room_id   TEXT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    next_seq  BIGINT NOT NULL DEFAULT 1
);

-- 6) Invite codes: >=128-bit random, only the SHA-256 hash is stored,
--    reusable until expiry or revocation.
CREATE TABLE IF NOT EXISTS room_invites (
    code_hash   TEXT PRIMARY KEY,
    room_id     TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    created_by  TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '24 hours',
    revoked_at  TIMESTAMPTZ
);

-- 7) Streaming cursors per (room, key, session).
CREATE TABLE IF NOT EXISTS room_caller_cursors (
    room_id           TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    api_key_id        TEXT NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
    session_key       TEXT NOT NULL,
    last_received_seq BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (room_id, api_key_id, session_key)
);

-- 8) Caller keys bound to a room (NULL = ordinary key).
ALTER TABLE api_keys ADD COLUMN IF NOT EXISTS room_id TEXT REFERENCES conversations(id);
CREATE INDEX IF NOT EXISTS idx_api_keys_room ON api_keys (room_id) WHERE room_id IS NOT NULL;
