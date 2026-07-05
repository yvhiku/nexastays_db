-- Reusable Identity Verification: ecosystem-level KYC reuse across Nexa services
-- Only VERIFIED, non-expired documents eligible. Driver-specific compliance remains separate.

CREATE TABLE IF NOT EXISTS reusable_identity_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unified_identity_id UUID NOT NULL UNIQUE REFERENCES unified_identities(id) ON DELETE CASCADE,
  kyc_provider VARCHAR(50),
  verification_reference VARCHAR(100),
  kyc_status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  identity_verified BOOLEAN NOT NULL DEFAULT FALSE,
  verification_level VARCHAR(30),
  document_type VARCHAR(50),
  document_number_masked VARCHAR(32),
  first_verified_at TIMESTAMPTZ,
  last_verified_at TIMESTAMPTZ,
  expiry_date DATE,
  selfie_verified BOOLEAN NOT NULL DEFAULT FALSE,
  reusable_across_services BOOLEAN NOT NULL DEFAULT FALSE,
  reuse_block_reason VARCHAR(50),
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reusable_kyc_unified_identity ON reusable_identity_verifications(unified_identity_id);
CREATE INDEX IF NOT EXISTS idx_reusable_kyc_status ON reusable_identity_verifications(kyc_status);
CREATE INDEX IF NOT EXISTS idx_reusable_kyc_expiry ON reusable_identity_verifications(expiry_date);

COMMENT ON TABLE reusable_identity_verifications IS 'Reusable KYC for UnifiedIdentity; VERIFIED + non-expired only';
