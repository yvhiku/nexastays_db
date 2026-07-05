-- Nexa Stays: core schema (standalone DB — no users table, no FK to Identity)
-- user_id / guest_user_id / host_user_id = Identity account UUID (JWT sub)

BEGIN;

CREATE TABLE IF NOT EXISTS stays_host_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE,
  host_verification_status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
    CHECK (host_verification_status IN ('PENDING', 'APPROVED', 'REJECTED')),
  document_type VARCHAR(20),
  document_number_hash VARCHAR(128),
  document_front_asset_id UUID,
  document_back_asset_id UUID,
  selfie_asset_id UUID,
  submitted_at TIMESTAMPTZ,
  reviewed_at TIMESTAMPTZ,
  reviewed_by VARCHAR(100),
  rejection_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_host_profiles_user ON stays_host_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_stays_host_profiles_status ON stays_host_profiles(host_verification_status);

COMMENT ON COLUMN stays_host_profiles.user_id IS 'Identity account id (JWT sub); not a FK';

CREATE TABLE IF NOT EXISTS stays_listings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id UUID NOT NULL,
  title VARCHAR(200) NOT NULL,
  listing_type VARCHAR(20) NOT NULL CHECK (listing_type IN ('APARTMENT', 'HOTEL', 'RIAD', 'VILLA')),
  city VARCHAR(100) NOT NULL,
  address_encrypted TEXT,
  geo_lat DECIMAL(10, 7),
  geo_lng DECIMAL(11, 7),
  status VARCHAR(30) NOT NULL DEFAULT 'DRAFT'
    CHECK (status IN ('DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED', 'LIVE')),
  checkin_time TIME NOT NULL DEFAULT '14:00',
  checkout_time TIME NOT NULL DEFAULT '11:00',
  description TEXT,
  instant_booking BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_listings_host ON stays_listings(host_user_id);
CREATE INDEX IF NOT EXISTS idx_stays_listings_status ON stays_listings(status);
CREATE INDEX IF NOT EXISTS idx_stays_listings_city ON stays_listings(city);
CREATE INDEX IF NOT EXISTS idx_stays_listings_geo ON stays_listings(geo_lat, geo_lng);

CREATE TABLE IF NOT EXISTS stays_listing_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES stays_listings(id) ON DELETE CASCADE,
  pets_policy VARCHAR(30) CHECK (pets_policy IN ('ALLOWED', 'DOGS_CATS', 'NO')),
  smoking_policy VARCHAR(20) CHECK (smoking_policy IN ('ALLOWED', 'NOT_ALLOWED')),
  quiet_hours BOOLEAN DEFAULT false,
  couples_welcome BOOLEAN DEFAULT true,
  max_guests INT NOT NULL DEFAULT 4,
  amenities JSONB DEFAULT '[]',
  extra_rules_text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(listing_id)
);

CREATE TABLE IF NOT EXISTS stays_listing_media (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES stays_listings(id) ON DELETE CASCADE,
  kind VARCHAR(20) NOT NULL CHECK (kind IN ('PHOTO', 'VIDEO', 'WALKTHROUGH')),
  asset_id UUID NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_required BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_listing_media_listing ON stays_listing_media(listing_id);

CREATE TABLE IF NOT EXISTS stays_availability_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES stays_listings(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  is_blocked BOOLEAN NOT NULL DEFAULT false,
  source VARCHAR(20) CHECK (source IN ('HOST', 'ADMIN', 'BOOKING')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(listing_id, date)
);

CREATE INDEX IF NOT EXISTS idx_stays_availability_listing_date ON stays_availability_blocks(listing_id, date);

CREATE TABLE IF NOT EXISTS stays_rate_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES stays_listings(id) ON DELETE CASCADE,
  currency CHAR(3) NOT NULL DEFAULT 'MAD',
  base_price DECIMAL(18, 2) NOT NULL CHECK (base_price > 0),
  weekend_price DECIMAL(18, 2),
  cleaning_fee DECIMAL(18, 2) DEFAULT 0,
  deposit_policy_text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(listing_id)
);

CREATE TABLE IF NOT EXISTS stays_check_in_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES stays_listings(id) ON DELETE CASCADE,
  full_name VARCHAR(100) NOT NULL,
  phone_encrypted TEXT NOT NULL,
  role VARCHAR(20) NOT NULL CHECK (role IN ('OWNER', 'CO_HOST', 'AGENT')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(listing_id)
);

CREATE TABLE IF NOT EXISTS stays_bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES stays_listings(id) ON DELETE RESTRICT,
  guest_user_id UUID NOT NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'INITIATED'
    CHECK (status IN (
      'INITIATED', 'PAYMENT_PENDING', 'CONFIRMED',
      'CHECKED_IN', 'COMPLETED',
      'CANCELLED_BY_GUEST', 'CANCELLED_BY_HOST', 'EXPIRED'
    )),
  checkin_date DATE NOT NULL,
  checkout_date DATE NOT NULL,
  guest_count INT NOT NULL DEFAULT 1,
  total_subtotal DECIMAL(18, 2) NOT NULL,
  guest_fee DECIMAL(18, 2) NOT NULL DEFAULT 0,
  host_fee DECIMAL(18, 2) NOT NULL DEFAULT 0,
  total_paid DECIMAL(18, 2),
  payout_amount DECIMAL(18, 2),
  currency CHAR(3) NOT NULL DEFAULT 'MAD',
  idempotency_key VARCHAR(64) UNIQUE,
  payment_intent_id VARCHAR(128),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  confirmed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_stays_bookings_listing ON stays_bookings(listing_id);
CREATE INDEX IF NOT EXISTS idx_stays_bookings_guest ON stays_bookings(guest_user_id);
CREATE INDEX IF NOT EXISTS idx_stays_bookings_status ON stays_bookings(status);
CREATE INDEX IF NOT EXISTS idx_stays_bookings_dates ON stays_bookings(checkin_date, checkout_date);

CREATE TABLE IF NOT EXISTS stays_booking_occupants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES stays_bookings(id) ON DELETE CASCADE,
  full_name VARCHAR(100) NOT NULL,
  id_number VARCHAR(64),
  is_primary BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_booking_occupants_booking ON stays_booking_occupants(booking_id);

CREATE TABLE IF NOT EXISTS stays_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind VARCHAR(20) NOT NULL CHECK (kind IN ('PHOTO', 'VIDEO', 'DOCUMENT')),
  mime_type VARCHAR(100),
  storage_key VARCHAR(512) NOT NULL,
  size_bytes BIGINT,
  checksum VARCHAR(64),
  created_by UUID,
  visibility VARCHAR(20) DEFAULT 'PRIVATE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_assets_storage_key ON stays_assets(storage_key);

COMMIT;
