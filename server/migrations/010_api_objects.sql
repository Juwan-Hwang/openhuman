-- 010: generic OpenAI-style API object persistence — vector stores and
-- their file batches, assistants, threads, runs, agents and sessions all
-- survive restarts as (obj, input, history) triples keyed by id. obj is
-- the public API object; input/history are private working state that
-- never leak into responses. A per-owner per-kind cap evicts the
-- least-recently-active objects. Re-runnable; rollback is
-- 010_api_objects_down.sql, run by hand only.

CREATE TABLE IF NOT EXISTS api_objects (
    id TEXT PRIMARY KEY,
    owner TEXT NOT NULL,
    -- obj->>'object': "vector_store", "thread", "thread.run", "assistant", ...
    object_kind TEXT NOT NULL,
    obj JSONB NOT NULL,
    input JSONB NOT NULL,
    history JSONB NOT NULL,
    last_active_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS api_objects_owner_kind ON api_objects (owner, object_kind, last_active_at DESC);
