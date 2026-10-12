-- OpenHuman — Phase 7 Migration: Agent Capabilities & Contexts
--
-- Tables:
--   agent_capabilities  — tools an agent exposes to humans
--   agent_contexts      — non-sensitive runtime metadata per agent
--
-- See: protocol/internal-model/capability.md §3 and §4

-- ── 8. Agent Capabilities ──
--
-- Each row is one tool/capability that an agent publishes via
-- `capability.manifest`. The composite key (agent_id, id) ensures
-- uniqueness — publishing a new manifest upserts all rows.

CREATE TABLE IF NOT EXISTS agent_capabilities (
    agent_id      TEXT         NOT NULL REFERENCES agent_identities(id) ON DELETE CASCADE,
    id            TEXT         NOT NULL,
    name          TEXT         NOT NULL,
    description   TEXT,
    category      TEXT,
    input_schema  JSONB,
    output_schema JSONB,
    ui_schema     JSONB,
    permissions   JSONB        NOT NULL DEFAULT '[]'::jsonb,
    metadata      JSONB        NOT NULL DEFAULT '{}'::jsonb,
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    PRIMARY KEY (agent_id, id)
);

CREATE INDEX IF NOT EXISTS idx_agent_caps_agent ON agent_capabilities (agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_caps_category ON agent_capabilities (category);

-- ── 9. Agent Contexts ──
--
-- One row per agent. Stores non-sensitive runtime metadata:
-- system_prompt, model info, runtime info, environment info.
-- Must NOT contain secrets, tokens, or passwords.

CREATE TABLE IF NOT EXISTS agent_contexts (
    agent_id      TEXT         PRIMARY KEY REFERENCES agent_identities(id) ON DELETE CASCADE,
    system_prompt TEXT,
    model         JSONB,
    runtime       JSONB,
    environment   JSONB,
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
