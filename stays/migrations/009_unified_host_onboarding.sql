-- Unified host onboarding on stays_host_profiles (mobile + web single queue)
-- Migrates pending host_applications into profiles; keeps host_applications table for history.

BEGIN;

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS application_status VARCHAR(20) NOT NULL DEFAULT 'DRAFT';

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS identity_status VARCHAR(20) NOT NULL DEFAULT 'NOT_STARTED';

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS source VARCHAR(20) NOT NULL DEFAULT 'UNKNOWN';

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS submitted_from VARCHAR(64);

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS sumsub_applicant_id VARCHAR(128);

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS full_name VARCHAR(255);

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS email VARCHAR(255);

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS phone VARCHAR(50);

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS city VARCHAR(100);

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS host_type VARCHAR(50);

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS hosting_policies_accepted_at TIMESTAMPTZ;

ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS identity_reused BOOLEAN NOT NULL DEFAULT FALSE;

-- Backfill application_status from legacy host_verification_status
UPDATE stays_host_profiles
SET application_status = CASE
  WHEN host_verification_status = 'APPROVED' THEN 'APPROVED'
  WHEN host_verification_status = 'REJECTED' THEN 'REJECTED'
  WHEN submitted_at IS NOT NULL THEN 'PENDING'
  ELSE 'DRAFT'
END
WHERE application_status = 'DRAFT' OR application_status IS NULL;

UPDATE stays_host_profiles
SET identity_status = CASE
  WHEN host_verification_status = 'APPROVED' AND reviewed_by = 'KYC_LINKED' THEN 'VERIFIED'
  WHEN document_front_asset_id IS NOT NULL OR selfie_asset_id IS NOT NULL THEN 'PENDING'
  ELSE 'NOT_STARTED'
END
WHERE identity_status = 'NOT_STARTED';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_stays_host_application_status') THEN
    ALTER TABLE stays_host_profiles ADD CONSTRAINT chk_stays_host_application_status
      CHECK (application_status IN ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_stays_host_identity_status') THEN
    ALTER TABLE stays_host_profiles ADD CONSTRAINT chk_stays_host_identity_status
      CHECK (identity_status IN ('NOT_STARTED', 'PENDING', 'VERIFIED', 'FAILED', 'NOT_REQUIRED'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_stays_host_onboarding_source') THEN
    ALTER TABLE stays_host_profiles ADD CONSTRAINT chk_stays_host_onboarding_source
      CHECK (source IN ('MOBILE', 'WEB', 'ADMIN', 'UNKNOWN'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_stays_host_profiles_application_status
  ON stays_host_profiles(application_status);

CREATE INDEX IF NOT EXISTS idx_stays_host_profiles_submitted_at
  ON stays_host_profiles(submitted_at DESC);

-- Migrate host_applications → stays_host_profiles (do not delete host_applications)
DO $$
DECLARE
  app RECORD;
  prof_id UUID;
  mapped_app_status VARCHAR(20);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'host_applications') THEN
    RETURN;
  END IF;

  FOR app IN
    SELECT * FROM host_applications ORDER BY created_at ASC
  LOOP
    mapped_app_status := CASE
      WHEN app.status IN ('PENDING', 'UNDER_REVIEW') THEN 'PENDING'
      WHEN app.status = 'APPROVED' THEN 'APPROVED'
      WHEN app.status = 'REJECTED' THEN 'REJECTED'
      ELSE 'PENDING'
    END;

    SELECT id INTO prof_id FROM stays_host_profiles WHERE user_id = app.applicant_user_id LIMIT 1;

    IF prof_id IS NULL THEN
      INSERT INTO stays_host_profiles (
        user_id,
        host_verification_status,
        application_status,
        identity_status,
        source,
        submitted_from,
        full_name,
        email,
        phone,
        submitted_at,
        reviewed_at,
        reviewed_by,
        rejection_reason,
        identity_reused,
        hosting_policies_accepted_at
      ) VALUES (
        app.applicant_user_id,
        CASE mapped_app_status
          WHEN 'APPROVED' THEN 'APPROVED'
          WHEN 'REJECTED' THEN 'REJECTED'
          ELSE 'PENDING'
        END,
        mapped_app_status,
        CASE WHEN app.identity_reused THEN 'VERIFIED' ELSE 'NOT_STARTED' END,
        'MOBILE',
        'MOBILE_BECOME_HOST',
        app.full_name,
        app.email,
        app.phone_number,
        COALESCE(app.reviewed_at, app.created_at),
        app.reviewed_at,
        app.reviewed_by,
        app.rejection_reason,
        COALESCE(app.identity_reused, FALSE),
        app.hosting_policies_accepted_at
      );
    ELSE
      UPDATE stays_host_profiles SET
        application_status = mapped_app_status,
        host_verification_status = CASE mapped_app_status
          WHEN 'APPROVED' THEN 'APPROVED'
          WHEN 'REJECTED' THEN 'REJECTED'
          ELSE host_verification_status
        END,
        source = COALESCE(NULLIF(source, 'UNKNOWN'), 'MOBILE'),
        submitted_from = COALESCE(submitted_from, 'MOBILE_BECOME_HOST'),
        full_name = COALESCE(full_name, app.full_name),
        email = COALESCE(email, app.email),
        phone = COALESCE(phone, app.phone_number),
        identity_reused = identity_reused OR COALESCE(app.identity_reused, FALSE),
        hosting_policies_accepted_at = COALESCE(hosting_policies_accepted_at, app.hosting_policies_accepted_at),
        submitted_at = COALESCE(submitted_at, app.created_at),
        reviewed_at = COALESCE(reviewed_at, app.reviewed_at),
        reviewed_by = COALESCE(reviewed_by, app.reviewed_by),
        rejection_reason = COALESCE(rejection_reason, app.rejection_reason)
      WHERE id = prof_id;
    END IF;
  END LOOP;
END $$;

COMMENT ON COLUMN stays_host_profiles.application_status IS 'Unified host onboarding: DRAFT|PENDING|APPROVED|REJECTED';
COMMENT ON COLUMN stays_host_profiles.identity_status IS 'Identity/KYC slice for host onboarding';
COMMENT ON COLUMN stays_host_profiles.source IS 'MOBILE|WEB|ADMIN|UNKNOWN';

COMMIT;
