-- Support CSAT: half-star ratings (0.5 increments), matching stay reviews.

BEGIN;

ALTER TABLE stays_support_ticket_csat
  DROP CONSTRAINT IF EXISTS stays_support_ticket_csat_rating_range;

ALTER TABLE stays_support_ticket_csat
  DROP CONSTRAINT IF EXISTS stays_support_ticket_csat_agent_rating_range;

ALTER TABLE stays_support_ticket_csat
  ALTER COLUMN rating TYPE NUMERIC(2, 1) USING rating::NUMERIC(2, 1);

ALTER TABLE stays_support_ticket_csat
  ALTER COLUMN agent_rating TYPE NUMERIC(2, 1) USING agent_rating::NUMERIC(2, 1);

ALTER TABLE stays_support_ticket_csat
  ADD CONSTRAINT stays_support_ticket_csat_rating_range
  CHECK (rating IN (0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5));

ALTER TABLE stays_support_ticket_csat
  ADD CONSTRAINT stays_support_ticket_csat_agent_rating_range
  CHECK (
    agent_rating IS NULL
    OR agent_rating IN (0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5)
  );

COMMIT;
