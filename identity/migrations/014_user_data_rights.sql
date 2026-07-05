ALTER TABLE users
  ADD COLUMN IF NOT EXISTS deletion_status VARCHAR(30) NOT NULL DEFAULT 'NONE',
  ADD COLUMN IF NOT EXISTS deletion_requested_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS deletion_scheduled_for TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS pii_anonymized_at TIMESTAMPTZ NULL;

CREATE INDEX IF NOT EXISTS idx_users_deletion_status
  ON users (deletion_status);
