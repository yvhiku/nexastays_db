-- Loop 4: ADMIN-only lightweight coaching notes

BEGIN;

CREATE TABLE IF NOT EXISTS stays_support_agent_coaching_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_user_id VARCHAR(128) NOT NULL,
  created_by VARCHAR(128) NOT NULL,
  note TEXT NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'OPEN',
  follow_up_at TIMESTAMPTZ NULL,
  completed_at TIMESTAMPTZ NULL,
  completed_by VARCHAR(128) NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT stays_support_agent_coaching_notes_status_check
    CHECK (status IN ('OPEN', 'COMPLETED')),
  CONSTRAINT stays_support_agent_coaching_notes_note_len
    CHECK (char_length(note) BETWEEN 1 AND 4000)
);

CREATE INDEX IF NOT EXISTS idx_stays_support_coaching_agent_created
  ON stays_support_agent_coaching_notes (agent_user_id, created_at DESC);

COMMIT;
