-- KYC Profile: front/back document URLs, document metadata, hashed CNIE number
-- Run this if not using TypeORM synchronize (e.g. production).

ALTER TABLE kyc_profiles
  ADD COLUMN IF NOT EXISTS document_front_url VARCHAR(2048) NULL,
  ADD COLUMN IF NOT EXISTS document_back_url VARCHAR(2048) NULL,
  ADD COLUMN IF NOT EXISTS document_type VARCHAR(50) NULL,
  ADD COLUMN IF NOT EXISTS document_country VARCHAR(10) NULL,
  ADD COLUMN IF NOT EXISTS national_id_number_hash VARCHAR(128) NULL;

COMMENT ON COLUMN kyc_profiles.document_front_url IS 'Relative path or URL to document front image';
COMMENT ON COLUMN kyc_profiles.document_back_url IS 'Relative path or URL to document back image';
COMMENT ON COLUMN kyc_profiles.document_type IS 'CNIE, PASSPORT, NATIONAL_ID, DRIVING_LICENSE';
COMMENT ON COLUMN kyc_profiles.document_country IS 'ISO alpha-2 country code (e.g. MA, FR)';
COMMENT ON COLUMN kyc_profiles.national_id_number_hash IS 'Hashed Moroccan CNIE number; never store raw';
