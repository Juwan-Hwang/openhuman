-- 008: API task cards — the units of human work behind the non-chat
-- OpenAI endpoints (images, audio, completions; later batches and
-- assistant sessions). Persisted so per-owner quotas survive restarts
-- and work in flight when the server stops can be failed honestly
-- (fail_in_flight_tasks at boot) instead of vanishing.
-- Re-runnable like the rest of the series; rollback is
-- 008_task_cards_down.sql, run by hand only.

CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    -- The API key owner's agent id (same id space as agents.id).
    owner TEXT NOT NULL,
    -- The endpoint kind: 'images', 'audio.speech', 'completions', ...
    api TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'completed', 'failed')),
    -- The seat conversation the task rides on, once chat routing opens it.
    conversation_id TEXT,
    -- What the caller asked for (endpoint-shaped; for audits and retries).
    request JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- The seat's answer, once delivered.
    answer JSONB,
    -- Why it failed, when it did.
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Owner history (status endpoints, quota pruning) and the boot-time
-- in-flight sweep both have their own index.
CREATE INDEX IF NOT EXISTS tasks_owner_created ON tasks (owner, created_at DESC);
CREATE INDEX IF NOT EXISTS tasks_in_flight ON tasks (status) WHERE status IN ('queued', 'running');
