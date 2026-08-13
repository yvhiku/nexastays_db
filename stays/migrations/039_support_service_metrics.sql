-- Support & Trust Phase 3 — service metrics timestamps
-- resolved_at already exists on stays_support_tickets (036).

BEGIN;

ALTER TABLE stays_support_tickets
  ADD COLUMN IF NOT EXISTS first_admin_response_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ NULL;

-- Analytics / queue: status + created_at (037 has status_updated and priority separately).
CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_status_created
  ON stays_support_tickets (status, created_at DESC);

COMMIT;
