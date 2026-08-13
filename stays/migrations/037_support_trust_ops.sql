-- Support & Trust Operations Phase 1
-- Normalize report/safety statuses, persist conversation context, enforce
-- one ticket per report/safety issue, add requester_email + queue indexes.
--
-- conversation_id on stays_support_tickets remains UUID UNIQUE NOT NULL.
-- No reviewed_at / escalated_at / dismissed_at columns.
-- Dismissed rows are never deleted.

BEGIN;

-- ---------------------------------------------------------------------------
-- Report / safety status: drop inline CHECKs, uppercase, re-constrain
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  con_name text;
BEGIN
  SELECT c.conname INTO con_name
  FROM pg_constraint c
  JOIN pg_class t ON c.conrelid = t.oid
  JOIN pg_namespace n ON t.relnamespace = n.oid
  WHERE t.relname = 'stays_conversation_reports'
    AND n.nspname = current_schema()
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%status%';

  IF con_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE stays_conversation_reports DROP CONSTRAINT %I',
      con_name
    );
  END IF;
END $$;

DO $$
DECLARE
  con_name text;
BEGIN
  SELECT c.conname INTO con_name
  FROM pg_constraint c
  JOIN pg_class t ON c.conrelid = t.oid
  JOIN pg_namespace n ON t.relnamespace = n.oid
  WHERE t.relname = 'stays_safety_issues'
    AND n.nspname = current_schema()
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%status%';

  IF con_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE stays_safety_issues DROP CONSTRAINT %I',
      con_name
    );
  END IF;
END $$;

UPDATE stays_conversation_reports
SET status = UPPER(status)
WHERE status IS DISTINCT FROM UPPER(status);

UPDATE stays_safety_issues
SET status = UPPER(status)
WHERE status IS DISTINCT FROM UPPER(status);

ALTER TABLE stays_conversation_reports
  ALTER COLUMN status SET DEFAULT 'OPEN';

ALTER TABLE stays_safety_issues
  ALTER COLUMN status SET DEFAULT 'OPEN';

ALTER TABLE stays_conversation_reports
  DROP CONSTRAINT IF EXISTS stays_conversation_reports_status_check;

ALTER TABLE stays_conversation_reports
  ADD CONSTRAINT stays_conversation_reports_status_check
  CHECK (status IN ('OPEN', 'REVIEWED', 'ESCALATED', 'DISMISSED'));

ALTER TABLE stays_safety_issues
  DROP CONSTRAINT IF EXISTS stays_safety_issues_status_check;

ALTER TABLE stays_safety_issues
  ADD CONSTRAINT stays_safety_issues_status_check
  CHECK (status IN ('OPEN', 'REVIEWED', 'ESCALATED', 'DISMISSED'));

-- ---------------------------------------------------------------------------
-- Persist booking / listing / reported user on canonical records
-- ---------------------------------------------------------------------------
ALTER TABLE stays_conversation_reports
  ADD COLUMN IF NOT EXISTS booking_id UUID REFERENCES stays_bookings(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS listing_id UUID REFERENCES stays_listings(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reported_user_id VARCHAR(128);

ALTER TABLE stays_safety_issues
  ADD COLUMN IF NOT EXISTS booking_id UUID REFERENCES stays_bookings(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS listing_id UUID REFERENCES stays_listings(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reported_user_id VARCHAR(128);

UPDATE stays_conversation_reports r
SET
  booking_id = COALESCE(r.booking_id, c.booking_id),
  listing_id = COALESCE(r.listing_id, c.listing_id),
  reported_user_id = COALESCE(
    r.reported_user_id,
    CASE
      WHEN r.reporter_user_id = c.guest_user_id THEN c.host_user_id
      WHEN r.reporter_user_id = c.host_user_id THEN c.guest_user_id
      ELSE NULL
    END
  )
FROM stays_conversations c
WHERE r.conversation_id = c.id;

UPDATE stays_safety_issues s
SET
  booking_id = COALESCE(s.booking_id, c.booking_id),
  listing_id = COALESCE(s.listing_id, c.listing_id),
  reported_user_id = COALESCE(
    s.reported_user_id,
    CASE
      WHEN s.reporter_user_id = c.guest_user_id THEN c.host_user_id
      WHEN s.reporter_user_id = c.host_user_id THEN c.guest_user_id
      ELSE NULL
    END
  )
FROM stays_conversations c
WHERE s.conversation_id = c.id;

CREATE INDEX IF NOT EXISTS idx_stays_conversation_reports_booking
  ON stays_conversation_reports (booking_id)
  WHERE booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stays_conversation_reports_listing
  ON stays_conversation_reports (listing_id)
  WHERE listing_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_stays_safety_issues_booking
  ON stays_safety_issues (booking_id)
  WHERE booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stays_safety_issues_listing
  ON stays_safety_issues (listing_id)
  WHERE listing_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- One support ticket per report / safety issue
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_stays_support_tickets_report_id
  ON stays_support_tickets (report_id)
  WHERE report_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_stays_support_tickets_safety_issue_id
  ON stays_support_tickets (safety_issue_id)
  WHERE safety_issue_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Ticket search snapshot + queue indexes
-- conversation_id is NOT altered (remains UUID UNIQUE NOT NULL).
-- ticket_number already unique; requester_user_id already indexed (036).
-- ---------------------------------------------------------------------------
ALTER TABLE stays_support_tickets
  ADD COLUMN IF NOT EXISTS requester_email VARCHAR(256);

CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_status_updated
  ON stays_support_tickets (status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_priority
  ON stays_support_tickets (priority);

CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_category
  ON stays_support_tickets (category);

CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_assigned_admin
  ON stays_support_tickets (assigned_admin_id)
  WHERE assigned_admin_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_customer_name
  ON stays_support_tickets (customer_name);

CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_requester_email
  ON stays_support_tickets (requester_email);

COMMIT;
