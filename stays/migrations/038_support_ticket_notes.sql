-- Support & Trust Phase 2 — internal ticket notes (append-only)
-- Notes are operational metadata only; never mirrored into stays_messages.

BEGIN;

CREATE TABLE IF NOT EXISTS stays_support_ticket_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL
    REFERENCES stays_support_tickets (id) ON DELETE CASCADE,
  author_admin_id VARCHAR(128) NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT stays_support_ticket_notes_body_len
    CHECK (char_length(body) <= 5000 AND char_length(body) >= 1)
);

CREATE INDEX IF NOT EXISTS idx_stays_support_ticket_notes_ticket_created
  ON stays_support_ticket_notes (ticket_id, created_at ASC, id ASC);

COMMIT;
