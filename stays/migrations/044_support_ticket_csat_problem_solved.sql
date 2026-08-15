-- Support inbox polish: nullable problem_solved (no historical backfill)
-- and snapshotted review agent name at first close.

BEGIN;

ALTER TABLE stays_support_ticket_csat
  ADD COLUMN IF NOT EXISTS problem_solved BOOLEAN NULL;

ALTER TABLE stays_support_tickets
  ADD COLUMN IF NOT EXISTS review_agent_name VARCHAR(256) NULL;

COMMIT;
