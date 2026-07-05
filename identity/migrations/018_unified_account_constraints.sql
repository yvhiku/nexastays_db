-- Strengthen unified account system with database-level constraints and indexes.
-- Requires migrations 024, 026, 028, 029. See backend/docs/unified-account-constraints.md
--
-- Pre-check for MERCHANT duplicates (if migration fails):
--   SELECT unified_identity_id, count(*) FROM users
--   WHERE account_type = 'MERCHANT' AND unified_identity_id IS NOT NULL
--   GROUP BY unified_identity_id HAVING count(*) > 1;

-- 1. account_type CHECK constraint (validates enum values)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_account_type') THEN
    ALTER TABLE users DROP CONSTRAINT chk_users_account_type;
  END IF;
  ALTER TABLE users ADD CONSTRAINT chk_users_account_type
    CHECK (account_type IN ('CONSUMER', 'DRIVER', 'COURIER', 'HOST', 'MERCHANT', 'ADMIN'));
EXCEPTION
  WHEN duplicate_object THEN NULL; -- constraint with same def may exist
END $$;

-- 2. One MERCHANT per unified_identity_id (business rule: one merchant per person; can relax for franchise)
-- Skip if duplicates exist; run pre-check query above first and resolve.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_merchant_per_unified_identity
  ON users(unified_identity_id)
  WHERE account_type = 'MERCHANT' AND unified_identity_id IS NOT NULL;

COMMENT ON INDEX uniq_merchant_per_unified_identity IS 'One MERCHANT per UnifiedIdentity; relax if franchise/multi-venue needed';

-- 3. Composite index for fast (unified_identity_id, account_type) lookups
CREATE INDEX IF NOT EXISTS idx_users_unified_identity_account_type
  ON users(unified_identity_id, account_type)
  WHERE unified_identity_id IS NOT NULL;

COMMENT ON INDEX idx_users_unified_identity_account_type IS 'Fast findByUnifiedIdentityIdAndAccountType lookups';
