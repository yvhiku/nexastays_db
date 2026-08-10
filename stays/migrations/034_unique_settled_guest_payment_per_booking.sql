-- P2 financial integrity: at most one settled GUEST_PAYMENT per booking.
-- Application locking already enforces this; the database must guarantee it.
-- Do NOT delete financial rows. If duplicates exist, fail loudly for manual remediation.

DO $$
DECLARE
  dup_count integer;
BEGIN
  SELECT COUNT(*) INTO dup_count
  FROM (
    SELECT booking_id
    FROM stays_ledger_entries
    WHERE type = 'GUEST_PAYMENT'
      AND status = 'SETTLED'
    GROUP BY booking_id
    HAVING COUNT(*) > 1
  ) duplicates;

  IF dup_count > 0 THEN
    RAISE EXCEPTION
      'Migration 034 blocked: % booking(s) have duplicate settled GUEST_PAYMENT rows. Resolve manually before creating uniqueness index.',
      dup_count;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_stays_ledger_settled_guest_payment_unique
  ON stays_ledger_entries (booking_id)
  WHERE type = 'GUEST_PAYMENT'
    AND status = 'SETTLED';
