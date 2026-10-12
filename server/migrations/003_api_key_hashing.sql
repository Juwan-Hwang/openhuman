-- ═══════════════════════════════════════════════════════════
-- Migration 003 — API key hashing + conversation scoping index
-- ═══════════════════════════════════════════════════════════
--
-- Context
-- -------
-- `api_keys` carried two representations of the same secret:
--
--   * `raw_key`  — the plaintext key. Authentication queried
--                  `WHERE raw_key = $1`, so every valid credential sat in
--                  the database in the clear.
--
--   * `key_hash` — advertised as SHA-256 but actually populated by
--                  `DefaultHasher`: a 64-bit non-cryptographic SipHash whose
--                  output is **not stable across process restarts** (nor
--                  across Rust versions). It could never serve as a lookup
--                  key, which is precisely why the plaintext comparison
--                  existed in the first place.
--
-- This migration finishes what that TODO deferred:
--
--   1. Re-derives `key_hash` from `raw_key` with real SHA-256.
--   2. Drops the plaintext column outright.
--
-- Order matters — the backfill must complete before the column disappears.
-- The whole block is guarded by a column-existence check, so it is safe to
-- re-run: once `raw_key` is gone the block becomes a no-op.
--
-- Requires pgcrypto (declared in 001_init.sql) for `digest()`.
--
-- Caveat: rows whose `raw_key` was already NULL cannot be re-hashed, and
-- keep whatever `key_hash` they had. Those keys stop authenticating after
-- this migration — reissue them.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_name = 'api_keys'
           AND column_name = 'raw_key'
    ) THEN
        -- Backfill: only rows that do not already hold the correct digest.
        UPDATE api_keys
           SET key_hash = encode(digest(raw_key, 'sha256'), 'hex')
         WHERE raw_key IS NOT NULL
           AND raw_key <> ''
           AND key_hash IS DISTINCT FROM encode(digest(raw_key, 'sha256'), 'hex');

        -- Drop the plaintext column. Anything still referencing raw_key is
        -- a stale build and must be redeployed before this runs.
        ALTER TABLE api_keys DROP COLUMN raw_key;
    END IF;
END $$;

-- The demonstration key seeded in 001 must resolve under the new scheme.
-- No-op if it already holds the right digest (the backfill above handles it).
UPDATE api_keys
   SET key_hash = encode(digest('ohk_demo_alice_codex', 'sha256'), 'hex')
 WHERE id = 'key_demo_001'
   AND key_hash IS DISTINCT FROM encode(digest('ohk_demo_alice_codex', 'sha256'), 'hex');

-- ── Conversation scoping index ──
--
-- Conversations are now resolved by (agent, human, metadata->>'session_key')
-- instead of by agent alone, so each chat window maps to its own thread.
-- That lookup filters on the JSONB expression below; without this index it
-- degrades into a sequential scan as transcripts accumulate.
CREATE INDEX IF NOT EXISTS idx_conversation_session_key
    ON conversations ((metadata->>'session_key'));
