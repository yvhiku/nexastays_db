-- Closed-loop Support OS (Loop 1 + Loop 2)
-- FOLLOW_UP_REQUIRED signal, immutable requester_language, agent skills, viewer leases

BEGIN;

ALTER TABLE stays_support_operational_signals
  DROP CONSTRAINT IF EXISTS stays_support_operational_signals_type_check;

ALTER TABLE stays_support_operational_signals
  ADD CONSTRAINT stays_support_operational_signals_type_check
  CHECK (signal_type IN (
    'REPEAT_REPORT',
    'REPEAT_SAFETY_REPORT',
    'MULTIPLE_OPEN_TICKETS',
    'SLA_ATTENTION',
    'SLA_BREACHED',
    'UNASSIGNED_HIGH_PRIORITY',
    'LOW_CSAT_PATTERN',
    'FOLLOW_UP_REQUIRED'
  ));

ALTER TABLE stays_support_tickets
  ADD COLUMN IF NOT EXISTS requester_language VARCHAR(10) NULL;

ALTER TABLE stays_support_tickets
  DROP CONSTRAINT IF EXISTS stays_support_tickets_requester_language_check;

ALTER TABLE stays_support_tickets
  ADD CONSTRAINT stays_support_tickets_requester_language_check
  CHECK (
    requester_language IS NULL
    OR requester_language IN ('ar', 'fr', 'en')
  );

CREATE OR REPLACE FUNCTION stays_text_array_is_unique(arr text[])
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT COALESCE(cardinality(arr), 0) =
    COALESCE((SELECT COUNT(DISTINCT x) FROM unnest(COALESCE(arr, '{}'::text[])) AS x), 0);
$$;

CREATE TABLE IF NOT EXISTS stays_support_agent_skills (
  agent_user_id VARCHAR(128) PRIMARY KEY,
  languages TEXT[] NOT NULL DEFAULT '{}'::text[],
  categories TEXT[] NOT NULL DEFAULT '{}'::text[],
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT stays_support_agent_skills_languages_check
    CHECK (languages <@ ARRAY['ar', 'fr', 'en']::text[]),
  CONSTRAINT stays_support_agent_skills_languages_unique
    CHECK (stays_text_array_is_unique(languages)),
  CONSTRAINT stays_support_agent_skills_categories_check
    CHECK (categories <@ ARRAY[
      'BOOKING',
      'PAYMENT',
      'REFUND',
      'CANCELLATION',
      'HOST',
      'GUEST',
      'LISTING',
      'KYC',
      'TECHNICAL',
      'FRAUD',
      'OTHER'
    ]::text[]),
  CONSTRAINT stays_support_agent_skills_categories_unique
    CHECK (stays_text_array_is_unique(categories))
);

CREATE TABLE IF NOT EXISTS stays_support_ticket_viewers (
  ticket_id UUID NOT NULL REFERENCES stays_support_tickets (id) ON DELETE CASCADE,
  viewer_id VARCHAR(128) NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (ticket_id, viewer_id)
);

CREATE INDEX IF NOT EXISTS idx_stays_support_ticket_viewers_expires
  ON stays_support_ticket_viewers (expires_at);

COMMIT;
