-- Property / unit-type foundation for adaptive listing wizard.
-- Keeps existing listings bookable at listing_id; room-level booking is a later phase.

BEGIN;

-- Location + booking model + typed JSON bags on listings
ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS booking_model VARCHAR(30)
    CHECK (booking_model IS NULL OR booking_model IN (
      'ENTIRE_PROPERTY',
      'PRIVATE_ROOM',
      'MULTI_UNIT',
      'ROOM_TYPES',
      'DORM_BEDS',
      'PRIVATE_ROOMS',
      'DORM_AND_PRIVATE',
      'BOTH'
    )),
  ADD COLUMN IF NOT EXISTS country VARCHAR(2) NOT NULL DEFAULT 'MA',
  ADD COLUMN IF NOT EXISTS neighborhood VARCHAR(120),
  ADD COLUMN IF NOT EXISTS postal_code VARCHAR(20),
  ADD COLUMN IF NOT EXISTS building_name VARCHAR(120),
  ADD COLUMN IF NOT EXISTS landmark VARCHAR(200),
  ADD COLUMN IF NOT EXISTS property_details JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS safety_features JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS policies JSONB NOT NULL DEFAULT '{}'::jsonb;

UPDATE stays_listings
SET booking_model = 'ENTIRE_PROPERTY'
WHERE booking_model IS NULL;

-- Bookable unit / room / dorm types under a listing
CREATE TABLE IF NOT EXISTS stays_listing_unit_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES stays_listings(id) ON DELETE CASCADE,
  kind VARCHAR(30) NOT NULL
    CHECK (kind IN (
      'APARTMENT_UNIT',
      'HOTEL_ROOM',
      'RIAD_ROOM',
      'HOSTEL_DORM',
      'HOSTEL_PRIVATE',
      'VILLA_UNIT'
    )),
  name VARCHAR(160) NOT NULL,
  quantity INT NOT NULL DEFAULT 1 CHECK (quantity >= 1 AND quantity <= 500),
  max_guests INT NOT NULL DEFAULT 2 CHECK (max_guests >= 1 AND max_guests <= 50),
  bed_config JSONB NOT NULL DEFAULT '[]'::jsonb,
  size_sqm DECIMAL(8, 2),
  amenities JSONB NOT NULL DEFAULT '[]'::jsonb,
  pricing_unit VARCHAR(20) NOT NULL DEFAULT 'NIGHT'
    CHECK (pricing_unit IN ('NIGHT', 'BED_NIGHT', 'ROOM_NIGHT')),
  base_price DECIMAL(12, 2) NOT NULL DEFAULT 0 CHECK (base_price >= 0),
  currency VARCHAR(3) NOT NULL DEFAULT 'MAD',
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_unit_types_listing
  ON stays_listing_unit_types(listing_id);
CREATE INDEX IF NOT EXISTS idx_stays_unit_types_listing_sort
  ON stays_listing_unit_types(listing_id, sort_order);

-- Media categories + optional link to a unit type
ALTER TABLE stays_listing_media
  ADD COLUMN IF NOT EXISTS category VARCHAR(40)
    CHECK (category IS NULL OR category IN (
      'EXTERIOR',
      'ENTRANCE',
      'LIVING',
      'BEDROOM',
      'BATHROOM',
      'KITCHEN',
      'BALCONY',
      'WORKSPACE',
      'FACILITIES',
      'PARKING',
      'OUTDOOR',
      'COMMON',
      'RECEPTION',
      'ROOM',
      'DORM',
      'OTHER'
    )),
  ADD COLUMN IF NOT EXISTS unit_type_id UUID
    REFERENCES stays_listing_unit_types(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_cover BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_stays_listing_media_unit
  ON stays_listing_media(unit_type_id);

COMMIT;
