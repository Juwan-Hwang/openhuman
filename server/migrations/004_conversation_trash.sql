-- ═══════════════════════════════════════════════════════════
-- Migration 004 — Conversation trash (soft delete)
-- ═══════════════════════════════════════════════════════════
--
-- Context
-- -------
-- Deleting a conversation was destructive and irreversible: the only
-- option was removing the row, taking every message with it. One stray
-- confirmation and a transcript was gone for good, on every device.
--
-- This adds a trash model instead:
--
--   * `deleted_at IS NULL`     — live conversation (listed as before)
--   * `deleted_at IS NOT NULL` — in the trash; hidden from the default
--                                listing, restorable, still holds its
--                                messages
--
-- Nothing existing is deleted by this migration: every current row keeps
-- `deleted_at` NULL and stays visible.

ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone;

-- The default listing filters on `deleted_at IS NULL`, so a partial index
-- covering exactly the live rows keeps that scan small as the trash grows.
CREATE INDEX IF NOT EXISTS idx_conversations_live
    ON conversations (id)
    WHERE deleted_at IS NULL;

-- Finding what is in the trash, newest-discarded first.
CREATE INDEX IF NOT EXISTS idx_conversations_deleted
    ON conversations (deleted_at DESC)
    WHERE deleted_at IS NOT NULL;
