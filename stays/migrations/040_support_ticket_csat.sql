-- Support & Trust Phase 3 — one CSAT response per ticket

BEGIN;

CREATE TABLE IF NOT EXISTS stays_support_ticket_csat (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL UNIQUE
    REFERENCES stays_support_tickets (id) ON DELETE CASCADE,
  rating SMALLINT NOT NULL
    CONSTRAINT stays_support_ticket_csat_rating_range CHECK (rating BETWEEN 1 AND 5),
  comment TEXT NULL
    CONSTRAINT stays_support_ticket_csat_comment_len CHECK (
      comment IS NULL OR char_length(comment) <= 2000
    ),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stays_support_ticket_csat_submitted
  ON stays_support_ticket_csat (submitted_at DESC);

COMMIT;
