-- ADMIN accounts may omit phone_number (email + ADMIN_PASSWORD login only).
-- Placeholder phones were leaking into listings as UNVERIFIED (no KYC row).

BEGIN;

ALTER TABLE users ALTER COLUMN phone_number DROP NOT NULL;

UPDATE users
SET phone_number = NULL
WHERE account_type = 'ADMIN';

COMMIT;
