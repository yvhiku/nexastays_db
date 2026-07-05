-- Nexa Stays standalone database bootstrap
-- No FK to Identity DB — user ids are opaque UUIDs from Identity JWT (sub)

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS schema_migrations (
  filename VARCHAR(255) PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE schema_migrations IS 'Tracks applied SQL migrations from database/stays/migrations/';
