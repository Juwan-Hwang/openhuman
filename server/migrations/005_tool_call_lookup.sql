-- Migration 005 — Index for tool-result correlation lookups
--
-- Context
-- -------
-- When the agent sends a `role: "tool"` message, the server must recover
-- which stored tool call it answers (the agent only echoes `tool_call_id`).
-- That lookup filters on `messages.metadata->>'tool_call_id'` within one
-- conversation; without an index it scans the conversation's rows.
--
-- This adds an expression index covering exactly that predicate. Existing
-- rows are unaffected; the index only speeds up the correlation query.

CREATE INDEX IF NOT EXISTS idx_messages_tool_call_lookup
    ON messages (conversation_id, ((metadata ->> 'tool_call_id')))
    WHERE metadata ? 'tool_id';
