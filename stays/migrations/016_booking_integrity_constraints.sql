-- Nexa Stays booking integrity hardening
-- Adds DB-level invariants that complement the application transaction/lock checks.

BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE stays_bookings
  ADD CONSTRAINT chk_stays_bookings_checkout_after_checkin
  CHECK (checkout_date > checkin_date);

-- 001 created a global UNIQUE(idempotency_key). Keep the per-guest partial
-- uniqueness from 003 and remove any single-column global unique constraint.
DO $$
DECLARE
  constraint_name text;
BEGIN
  FOR constraint_name IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(c.conkey)
    WHERE t.relname = 'stays_bookings'
      AND c.contype = 'u'
      AND array_length(c.conkey, 1) = 1
      AND a.attname = 'idempotency_key'
  LOOP
    EXECUTE format('ALTER TABLE stays_bookings DROP CONSTRAINT %I', constraint_name);
  END LOOP;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_stays_bookings_idempotency_guest
  ON stays_bookings (guest_user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- Prevent overlapping active holds/bookings for the same listing at the DB
-- layer. This is a safety net under the existing SELECT ... FOR UPDATE flow.
ALTER TABLE stays_bookings
  ADD CONSTRAINT ex_stays_bookings_active_overlap
  EXCLUDE USING gist (
    listing_id WITH =,
    daterange(checkin_date, checkout_date, '[)') WITH &&
  )
  WHERE (status IN ('INITIATED', 'PAYMENT_PENDING', 'CONFIRMED', 'CHECKED_IN'));

-- Avoid more than one active payment attempt per booking while preserving
-- history for succeeded/failed/cancelled attempts.
CREATE UNIQUE INDEX IF NOT EXISTS idx_stays_payment_intents_one_pending_per_booking
  ON stays_payment_intents (booking_id)
  WHERE status = 'PENDING';

CREATE UNIQUE INDEX IF NOT EXISTS idx_stays_payment_intents_provider_unique
  ON stays_payment_intents (provider, provider_intent_id)
  WHERE provider_intent_id IS NOT NULL;

COMMIT;
