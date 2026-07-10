-- Store HMAC-SHA256 OTP digests (64 hex chars) instead of plaintext 6-digit codes.
ALTER TABLE otp_codes
  ALTER COLUMN code TYPE VARCHAR(128);
