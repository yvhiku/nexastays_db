-- Align kyc_profiles with KycProfile entity (columns added via monolith initdb, never in identity migrations)

ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS source VARCHAR(20) NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMP NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS reviewed_by VARCHAR(100) NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS rejection_reason TEXT NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS documents JSONB NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS national_id_number VARCHAR(64) NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS national_id_number_extracted VARCHAR(64) NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS full_name VARCHAR(200) NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS date_of_birth VARCHAR(16) NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS nationality VARCHAR(10) NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS email VARCHAR(150) NULL;
ALTER TABLE kyc_profiles ADD COLUMN IF NOT EXISTS aml_screening JSONB NULL;

COMMENT ON COLUMN kyc_profiles.source IS 'App/product that submitted KYC: PAY | GO | STAYS';
