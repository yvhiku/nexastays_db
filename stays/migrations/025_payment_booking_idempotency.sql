-- P0 remediation: prevent duplicate bookings and concurrent payment intents.

CREATE UNIQUE INDEX IF NOT EXISTS idx_stays_bookings_idempotency_key_unique
  ON stays_bookings (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_stays_payment_intents_booking_pending_unique
  ON stays_payment_intents (booking_id)
  WHERE status = 'PENDING';
