-- Ciphertext envelopes are longer than the original identifiers.
-- Existing plaintext remains readable during the rolling application migration
-- and is encrypted the next time the entity is saved.
ALTER TABLE kyc_profiles
  ALTER COLUMN national_id_number TYPE TEXT,
  ALTER COLUMN national_id_number_extracted TYPE TEXT;
