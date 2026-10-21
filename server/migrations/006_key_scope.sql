-- ═══════════════════════════════════════════════════════════
-- Migration 006 — key scope (caller / responder / both / revoked)
-- ═══════════════════════════════════════════════════════════
-- One key used to authenticate both sides of a conversation: anyone holding
-- the key handed to agent software could also connect to /ws and answer as
-- the human. Keys now carry the side they may act on. Existing keys default
-- to 'both' so an upgrade breaks nothing; issue split keys and retire them.
ALTER TABLE api_keys ADD COLUMN IF NOT EXISTS scope TEXT NOT NULL DEFAULT 'both';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'api_keys_scope_check') THEN
        ALTER TABLE api_keys ADD CONSTRAINT api_keys_scope_check
            CHECK (scope IN ('caller', 'responder', 'both', 'revoked'));
    END IF;
END $$;
