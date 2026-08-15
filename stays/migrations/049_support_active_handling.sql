-- Loop 3: viewing vs actively handling on the existing presence lease

BEGIN;

ALTER TABLE stays_support_ticket_viewers
  ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMPTZ NULL;

ALTER TABLE stays_support_ticket_viewers
  ADD COLUMN IF NOT EXISTS activity_state VARCHAR(16) NOT NULL DEFAULT 'VIEWING';

ALTER TABLE stays_support_ticket_viewers
  DROP CONSTRAINT IF EXISTS stays_support_ticket_viewers_activity_state_check;

ALTER TABLE stays_support_ticket_viewers
  ADD CONSTRAINT stays_support_ticket_viewers_activity_state_check
  CHECK (activity_state IN ('VIEWING', 'HANDLING'));

COMMIT;
