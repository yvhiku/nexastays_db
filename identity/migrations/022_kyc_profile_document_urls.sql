-- KYC Profile: add document image URL columns for uploaded ID document and selfie
-- Run this if not using TypeORM synchronize (e.g. production).

ALTER TABLE kyc_profiles
  ADD COLUMN IF NOT EXISTS id_document_url TEXT,
  ADD COLUMN IF NOT EXISTS selfie_url TEXT;

COMMENT ON COLUMN kyc_profiles.id_document_url IS 'URL or path to uploaded ID document image';
COMMENT ON COLUMN kyc_profiles.selfie_url IS 'URL or path to uploaded selfie image';
