-- Support CSAT & agent reviews Phase 1
-- Snapshot the handling agent at first CLOSED; extend CSAT with agent rating.

BEGIN;

ALTER TABLE stays_support_tickets
  ADD COLUMN IF NOT EXISTS review_agent_id VARCHAR(128) NULL;

ALTER TABLE stays_support_ticket_csat
  ADD COLUMN IF NOT EXISTS agent_rating SMALLINT NULL;

ALTER TABLE stays_support_ticket_csat
  ADD COLUMN IF NOT EXISTS agent_id VARCHAR(128) NULL;

ALTER TABLE stays_support_ticket_csat
  DROP CONSTRAINT IF EXISTS stays_support_ticket_csat_agent_rating_range;

ALTER TABLE stays_support_ticket_csat
  ADD CONSTRAINT stays_support_ticket_csat_agent_rating_range
  CHECK (agent_rating IS NULL OR agent_rating BETWEEN 1 AND 5);

ALTER TABLE stays_support_ticket_csat
  DROP CONSTRAINT IF EXISTS stays_support_ticket_csat_agent_pair;

ALTER TABLE stays_support_ticket_csat
  ADD CONSTRAINT stays_support_ticket_csat_agent_pair
  CHECK (
    (agent_id IS NULL AND agent_rating IS NULL)
    OR (agent_id IS NOT NULL AND agent_rating IS NOT NULL)
  );

CREATE INDEX IF NOT EXISTS idx_stays_support_ticket_csat_agent
  ON stays_support_ticket_csat (agent_id, submitted_at DESC)
  WHERE agent_id IS NOT NULL;

COMMIT;
