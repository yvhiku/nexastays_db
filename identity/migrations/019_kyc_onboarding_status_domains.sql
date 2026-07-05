-- KYC and onboarding status domain separation
-- See: backend/docs/kyc-onboarding-status-domains.md
--
-- Separates:
--   1. Person-level identity verification (UnifiedIdentity)
--   2. Reusable verification artifact (ReusableIdentityVerification)
--   3. Service account operational status (User)
--   4. Role onboarding status (host_verification_status, application status)

-- ============================================================================
-- 1. UnifiedIdentity: identity_verification_status
-- ============================================================================
ALTER TABLE unified_identities
  ADD COLUMN IF NOT EXISTS identity_verification_status VARCHAR(30);

-- Backfill from kyc_status
UPDATE unified_identities
SET identity_verification_status = CASE
  WHEN UPPER(COALESCE(kyc_status, '')) IN ('APPROVED', 'VERIFIED') THEN 'APPROVED'
  WHEN UPPER(COALESCE(kyc_status, '')) = 'REJECTED' THEN 'REJECTED'
  WHEN UPPER(COALESCE(kyc_status, '')) = 'EXPIRED' THEN 'EXPIRED'
  WHEN kyc_status IS NULL OR kyc_status = '' OR TRIM(kyc_status) = '' THEN 'NOT_STARTED'
  ELSE 'PENDING'
END
WHERE identity_verification_status IS NULL;

ALTER TABLE unified_identities
  ALTER COLUMN identity_verification_status SET DEFAULT 'NOT_STARTED';

UPDATE unified_identities
SET identity_verification_status = COALESCE(identity_verification_status, 'NOT_STARTED')
WHERE identity_verification_status IS NULL;

ALTER TABLE unified_identities
  ALTER COLUMN identity_verification_status SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_unified_identity_verification_status') THEN
    ALTER TABLE unified_identities ADD CONSTRAINT chk_unified_identity_verification_status
      CHECK (identity_verification_status IN (
        'NOT_STARTED', 'PENDING', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'EXPIRED'
      ));
  END IF;
END $$;

COMMENT ON COLUMN unified_identities.identity_verification_status IS 'Person-level identity verification. kyc_status kept for backward compat.';

-- ============================================================================
-- 2. ReusableIdentityVerification: verification_status
-- ============================================================================
ALTER TABLE reusable_identity_verifications
  ADD COLUMN IF NOT EXISTS verification_status VARCHAR(30);

-- Backfill: VERIFIED -> APPROVED, REJECTED, else PENDING
UPDATE reusable_identity_verifications
SET verification_status = CASE
  WHEN UPPER(COALESCE(kyc_status, 'PENDING')) = 'VERIFIED' THEN 'APPROVED'
  WHEN UPPER(COALESCE(kyc_status, 'PENDING')) = 'APPROVED' THEN 'APPROVED'
  WHEN UPPER(COALESCE(kyc_status, '')) = 'REJECTED' THEN 'REJECTED'
  WHEN UPPER(COALESCE(kyc_status, '')) = 'EXPIRED' THEN 'EXPIRED'
  ELSE 'PENDING'
END
WHERE verification_status IS NULL;

ALTER TABLE reusable_identity_verifications
  ALTER COLUMN verification_status SET DEFAULT 'PENDING';

UPDATE reusable_identity_verifications
SET verification_status = COALESCE(verification_status, 'PENDING')
WHERE verification_status IS NULL;

ALTER TABLE reusable_identity_verifications
  ALTER COLUMN verification_status SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_reusable_verification_status') THEN
    ALTER TABLE reusable_identity_verifications ADD CONSTRAINT chk_reusable_verification_status
      CHECK (verification_status IN (
        'NOT_STARTED', 'PENDING', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'EXPIRED'
      ));
  END IF;
END $$;

COMMENT ON COLUMN reusable_identity_verifications.verification_status IS 'Reusable verification artifact status. kyc_status kept for backward compat.';

-- ============================================================================
-- 3. User: service_account_status CHECK (users.status)
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_service_account_status') THEN
    ALTER TABLE users ADD CONSTRAINT chk_users_service_account_status
      CHECK (status IN (
        'PENDING', 'ACTIVE', 'SUSPENDED', 'REJECTED', 'DISABLED',
        'FROZEN', 'DELETION_PENDING'
      ));
  END IF;
EXCEPTION
  WHEN check_violation THEN
    -- Some rows may have invalid status; fix before adding constraint
    RAISE NOTICE 'chk_users_service_account_status: fix invalid status values first';
END $$;

COMMENT ON COLUMN users.status IS 'Service account operational status. See SERVICE_ACCOUNT_STATUS enum.';

-- ============================================================================
-- 4. host_applications: onboarding status (document only; keep existing CHECK)
-- ============================================================================
-- host_applications.status: PENDING, UNDER_REVIEW, APPROVED, REJECTED (onboarding)
-- go.registration_applications.status: same
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'host_applications') THEN
    COMMENT ON COLUMN host_applications.status IS 'Onboarding: PENDING/APPLICATION_SUBMITTED, UNDER_REVIEW, APPROVED, REJECTED';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'stays_host_profiles') THEN
    COMMENT ON COLUMN stays_host_profiles.host_verification_status IS 'Host onboarding: PENDING=under review, APPROVED=can list, REJECTED';
  END IF;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;
