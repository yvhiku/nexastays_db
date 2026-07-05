-- Nexa Stays Production Schema
-- Adds: cancellation policy, paid_at, idempotency uniqueness, payment intents,
-- ledger entries, audit logs, performance indexes

BEGIN;

-- 1. cancellation_policy on stays_listing_rules
ALTER TABLE stays_listing_rules
  ADD COLUMN IF NOT EXISTS cancellation_policy VARCHAR(20) DEFAULT 'MODERATE'
  CHECK (cancellation_policy IN ('FLEXIBLE', 'MODERATE', 'STRICT'));

-- 2. paid_at on stays_bookings
ALTER TABLE stays_bookings
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

-- 3. Idempotency: unique on (guest_user_id, idempotency_key) when idempotency_key present
-- Drop old unique on idempotency_key alone if exists (migration may have added it)
-- Create partial unique index
CREATE UNIQUE INDEX IF NOT EXISTS idx_stays_bookings_idempotency_guest
  ON stays_bookings (guest_user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- 4. stays_payment_intents
CREATE TABLE IF NOT EXISTS stays_payment_intents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES stays_bookings(id) ON DELETE RESTRICT,
  provider VARCHAR(50) NOT NULL,
  provider_intent_id VARCHAR(256),
  amount DECIMAL(18, 2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'MAD',
  status VARCHAR(30) NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED', 'CANCELLED')),
  idempotency_key VARCHAR(64) UNIQUE,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_payment_intents_booking ON stays_payment_intents(booking_id);
CREATE INDEX IF NOT EXISTS idx_stays_payment_intents_provider ON stays_payment_intents(provider, provider_intent_id);

-- 5. stays_ledger_entries
CREATE TABLE IF NOT EXISTS stays_ledger_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES stays_bookings(id) ON DELETE RESTRICT,
  type VARCHAR(30) NOT NULL
    CHECK (type IN ('GUEST_PAYMENT', 'HOST_PAYOUT', 'PLATFORM_FEE', 'REFUND')),
  amount DECIMAL(18, 2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'MAD',
  status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'SETTLED', 'FAILED')),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_ledger_entries_booking ON stays_ledger_entries(booking_id);

-- 6. stays_audit_logs
CREATE TABLE IF NOT EXISTS stays_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id UUID,
  actor_role VARCHAR(30),
  entity_type VARCHAR(50) NOT NULL,
  entity_id VARCHAR(128),
  action VARCHAR(50) NOT NULL,
  metadata JSONB DEFAULT '{}',
  ip VARCHAR(45),
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_audit_logs_entity ON stays_audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_stays_audit_logs_actor ON stays_audit_logs(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_stays_audit_logs_created ON stays_audit_logs(created_at);

-- 7. Performance indexes
CREATE INDEX IF NOT EXISTS idx_stays_bookings_listing_dates_status
  ON stays_bookings(listing_id, checkin_date, checkout_date, status);

CREATE INDEX IF NOT EXISTS idx_stays_availability_listing_date_blocked
  ON stays_availability_blocks(listing_id, date, is_blocked);

CREATE INDEX IF NOT EXISTS idx_stays_listings_city_status
  ON stays_listings(city, status);

CREATE INDEX IF NOT EXISTS idx_stays_host_profiles_user_status
  ON stays_host_profiles(user_id, host_verification_status);

COMMIT;
