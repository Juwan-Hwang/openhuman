ALTER TABLE messages DROP COLUMN IF EXISTS sender_name;
-- Rollback for 007_groups.sql. NOT run automatically: execute it by hand
-- after exporting any room data worth keeping — it destroys every room,
-- its log positions, invites, cursors, and unbinds room caller keys.
--
--   psql $DATABASE_URL -f migrations/007_groups_down.sql

-- Room caller keys first: their room_id references conversations.
DELETE FROM api_keys WHERE room_id IS NOT NULL;
-- Rooms and everything that cascades from them.
DELETE FROM conversations WHERE type = 'group';

DROP TABLE IF EXISTS room_caller_cursors;
DROP TABLE IF EXISTS room_invites;
DROP TABLE IF EXISTS room_counters;
ALTER TABLE api_keys DROP COLUMN IF EXISTS room_id;
ALTER TABLE messages DROP COLUMN IF EXISTS room_seq;
ALTER TABLE conversation_participants DROP COLUMN IF EXISTS first_visible_seq;

ALTER TABLE conversation_participants DROP CONSTRAINT IF EXISTS conversation_participants_role_check;
ALTER TABLE conversation_participants ADD CONSTRAINT conversation_participants_role_check
    CHECK (role IN ('initiator', 'responder', 'observer'));
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_type_check;
ALTER TABLE conversations ADD CONSTRAINT conversations_type_check
    CHECK (type IN ('agent_human', 'human_human'));
