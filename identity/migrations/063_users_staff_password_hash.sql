-- Per-user dashboard staff password (Argon2id) for provisioned Support Agents.
-- Super Admin bootstrap still uses ADMIN_EMAILS + env ADMIN_PASSWORD / ADMIN_PASSWORD_HASH.
ALTER TABLE users
ADD COLUMN IF NOT EXISTS staff_password_hash TEXT NULL;

COMMENT ON COLUMN users.staff_password_hash IS
  'Dashboard staff password (Argon2id). Super Admin bootstrap still uses env password.';
