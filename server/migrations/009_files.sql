-- 009: Files API persistence — uploaded and seat-produced files survive
-- restarts, with per-owner and global byte quotas enforced by the
-- repository (oldest files evicted first). Re-runnable; rollback is
-- 009_files_down.sql, run by hand only.

CREATE TABLE IF NOT EXISTS files (
    id TEXT PRIMARY KEY,
    owner TEXT NOT NULL,
    filename TEXT NOT NULL,
    mime TEXT NOT NULL,
    -- Server-set on seat-produced files; callers may never claim 'output'.
    purpose TEXT NOT NULL,
    bytes BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS files_owner_created ON files (owner, created_at DESC);
-- made_by_seat looks a file up by content to prove the seat produced it.
CREATE INDEX IF NOT EXISTS files_output_content ON files (purpose, md5(bytes)) WHERE purpose = 'output';
