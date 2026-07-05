-- identity_phone_numbers: phone numbers as verified login identifiers
-- UnifiedIdentity.id is the permanent identity key; phones are mutable.
-- Run after 024_unified_identity.

BEGIN;

-- 1. Create identity_phone_numbers table
CREATE TABLE IF NOT EXISTS identity_phone_numbers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  identity_id UUID NOT NULL REFERENCES unified_identities(id) ON DELETE CASCADE,
  phone_number VARCHAR(20) NOT NULL,
  normalized_phone_number VARCHAR(20) NOT NULL,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  verified_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_identity_phone_numbers_normalized
  ON identity_phone_numbers(normalized_phone_number);

CREATE INDEX IF NOT EXISTS idx_identity_phone_numbers_identity_id
  ON identity_phone_numbers(identity_id);

-- 2. Backfill from unified_identities.phone_number
INSERT INTO identity_phone_numbers (
  identity_id,
  phone_number,
  normalized_phone_number,
  is_primary,
  is_verified,
  verified_at,
  created_at,
  updated_at
)
SELECT
  ui.id,
  ui.phone_number,
  COALESCE(
    CASE
      WHEN ui.phone_number ~ '^\+\d{10,15}$' THEN ui.phone_number
      WHEN ui.phone_number ~ '^212\d{9}$' THEN '+' || ui.phone_number
      WHEN ui.phone_number ~ '^0?\d{9}$' THEN '+212' || REGEXP_REPLACE(ui.phone_number, '^0?', '')
      ELSE '+' || REGEXP_REPLACE(ui.phone_number, '\D', '', 'g')
    END,
    ui.phone_number
  ),
  TRUE,
  TRUE,
  ui.updated_at,
  ui.created_at,
  NOW()
FROM unified_identities ui
WHERE ui.phone_number IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM identity_phone_numbers ipn
    WHERE ipn.identity_id = ui.id
  )
ON CONFLICT (normalized_phone_number) DO NOTHING;

-- 3. Add any distinct user phones not yet in identity_phone_numbers (resilience)
INSERT INTO identity_phone_numbers (
  identity_id,
  phone_number,
  normalized_phone_number,
  is_primary,
  is_verified,
  verified_at,
  created_at,
  updated_at
)
SELECT
  sub.unified_identity_id,
  sub.phone_number,
  sub.norm,
  FALSE,
  TRUE,
  NOW(),
  sub.created_at,
  NOW()
FROM (
  SELECT DISTINCT ON (unified_identity_id, norm)
    unified_identity_id,
    phone_number,
    norm,
    created_at
  FROM (
    SELECT
      unified_identity_id,
      phone_number,
      COALESCE(
        CASE
          WHEN phone_number ~ '^\+\d{10,15}$' THEN phone_number
          WHEN phone_number ~ '^212\d{9}$' THEN '+' || phone_number
          WHEN phone_number ~ '^0?\d{9}$' THEN '+212' || REGEXP_REPLACE(phone_number, '^0?', '')
          ELSE '+212' || REGEXP_REPLACE(REGEXP_REPLACE(phone_number, '\D', '', 'g'), '^0?', '')
        END,
        phone_number
      ) AS norm,
      created_at
    FROM users
    WHERE unified_identity_id IS NOT NULL AND phone_number IS NOT NULL
  ) u
  ORDER BY unified_identity_id, norm, phone_number
) sub
WHERE NOT EXISTS (
  SELECT 1 FROM identity_phone_numbers ipn
  WHERE ipn.identity_id = sub.unified_identity_id
    AND ipn.normalized_phone_number = sub.norm
)
ON CONFLICT (normalized_phone_number) DO NOTHING;

-- 4. Deprecate phone_number on unified_identities (keep column for backward compat)
ALTER TABLE unified_identities ALTER COLUMN phone_number DROP NOT NULL;
ALTER TABLE unified_identities DROP CONSTRAINT IF EXISTS unified_identities_phone_number_key;
DROP INDEX IF EXISTS idx_unified_identities_phone;
COMMENT ON COLUMN unified_identities.phone_number IS 'DEPRECATED: use identity_phone_numbers. Prefer findIdentityByPhone for lookups.';

COMMIT;
