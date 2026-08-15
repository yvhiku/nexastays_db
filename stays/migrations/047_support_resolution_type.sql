-- Loop 3: optional structured resolution on support tickets

BEGIN;

ALTER TABLE stays_support_tickets
  ADD COLUMN IF NOT EXISTS resolution_type VARCHAR(32) NULL;

ALTER TABLE stays_support_tickets
  DROP CONSTRAINT IF EXISTS stays_support_tickets_resolution_type_check;

ALTER TABLE stays_support_tickets
  ADD CONSTRAINT stays_support_tickets_resolution_type_check
  CHECK (
    resolution_type IS NULL
    OR resolution_type IN (
      'ISSUE_FIXED',
      'INFORMATION_PROVIDED',
      'PAYMENT_RESOLVED',
      'BOOKING_UPDATED',
      'POLICY_EXPLAINED',
      'DUPLICATE',
      'NO_ACTION_POSSIBLE',
      'OTHER'
    )
  );

COMMIT;
