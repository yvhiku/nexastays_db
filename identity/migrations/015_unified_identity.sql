-- Unified Nexa Identity: ecosystem-level source of truth
-- One phone = one identity. Service-specific users link to this.

-- 1. Create unified_identities table
CREATE TABLE IF NOT EXISTS unified_identities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number VARCHAR(20) NOT NULL UNIQUE,
  full_name VARCHAR(255),
  email VARCHAR(255),
  date_of_birth DATE,
  city VARCHAR(100),
  address TEXT,
  profile_photo_url VARCHAR(500),
  preferred_language VARCHAR(10),
  identity_verified BOOLEAN NOT NULL DEFAULT FALSE,
  kyc_status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  kyc_level VARCHAR(20),
  account_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
  linked_services JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_unified_identities_phone ON unified_identities(phone_number);

-- 2. Add FK from users to unified_identities (nullable for migration safety)
ALTER TABLE users ADD COLUMN IF NOT EXISTS unified_identity_id UUID REFERENCES unified_identities(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_users_unified_identity_id ON users(unified_identity_id);

-- 3. Backfill: one unified_identity per distinct phone (use best user: CONSUMER first, else first)
WITH ranked AS (
  SELECT u.*,
    ROW_NUMBER() OVER (
      PARTITION BY u.phone_number
      ORDER BY CASE WHEN u.account_type = 'CONSUMER' THEN 0 ELSE 1 END,
               u.created_at ASC
    ) AS rn
  FROM users u
),
best AS (
  SELECT * FROM ranked WHERE rn = 1
),
services AS (
  SELECT phone_number,
    COALESCE(jsonb_agg(DISTINCT account_type) FILTER (WHERE account_type IS NOT NULL), '[]'::jsonb) AS svc
  FROM users GROUP BY phone_number
)
INSERT INTO unified_identities (
  phone_number, full_name, email, date_of_birth, city, profile_photo_url,
  identity_verified, kyc_status, account_status, linked_services, created_at, updated_at
)
SELECT
  b.phone_number,
  b.full_name,
  b.email,
  b.date_of_birth,
  b.city,
  b.profile_photo_url,
  (UPPER(COALESCE(b.kyc_status, 'PENDING')) IN ('APPROVED', 'VERIFIED')),
  COALESCE(b.kyc_status, 'PENDING'),
  COALESCE(b.status, 'ACTIVE'),
  s.svc,
  b.created_at,
  NOW()
FROM best b
JOIN services s ON s.phone_number = b.phone_number
WHERE NOT EXISTS (SELECT 1 FROM unified_identities ui WHERE ui.phone_number = b.phone_number);

-- 4. Link users to their unified_identity
UPDATE users u
SET unified_identity_id = ui.id
FROM unified_identities ui
WHERE u.phone_number = ui.phone_number AND u.unified_identity_id IS NULL;

COMMENT ON TABLE unified_identities IS 'Unified Nexa identity: one phone = one identity across Pay, Go, Stays, Driver';
