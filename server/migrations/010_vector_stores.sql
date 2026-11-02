-- 010: vector store persistence — stores and their file batches survive
-- restarts. The public API object lives in obj; the file entries (never
-- part of API responses) live in input. Per-owner caps evict the
-- least-recently-active objects of the same kind. Re-runnable; rollback
-- is 010_vector_stores_down.sql, run by hand only.

CREATE TABLE IF NOT EXISTS vector_objects (
    id TEXT PRIMARY KEY,
    owner TEXT NOT NULL,
    -- "vector_store" or "vector_store.files_batch" (obj->>'object').
    object_kind TEXT NOT NULL,
    obj JSONB NOT NULL,
    input JSONB NOT NULL,
    last_active_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS vector_objects_owner_kind ON vector_objects (owner, object_kind, last_active_at DESC);
