-- Repair orphaned pg_index entries left by a partial/failed CREATE INDEX (025).
-- Symptom: SELECT on stays_bookings fails with "could not open relation with OID …".

DO $$
DECLARE
  orphan oid;
  target_table text;
BEGIN
  FOR orphan, target_table IN
    SELECT i.indexrelid, t.relname
    FROM pg_index i
    LEFT JOIN pg_class c ON c.oid = i.indexrelid
    JOIN pg_class t ON t.oid = i.indrelid
    WHERE c.oid IS NULL
      AND t.relname IN ('stays_bookings', 'stays_payment_intents')
  LOOP
    DELETE FROM pg_depend WHERE objid = orphan;
    DELETE FROM pg_index WHERE indexrelid = orphan;
    RAISE NOTICE 'Removed orphaned index catalog entry % on %', orphan, target_table;
  END LOOP;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_stays_bookings_idempotency_key_unique
  ON stays_bookings (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_stays_payment_intents_booking_pending_unique
  ON stays_payment_intents (booking_id)
  WHERE status = 'PENDING';
