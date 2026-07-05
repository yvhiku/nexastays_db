-- Enforce one CONSUMER account per unified_identity_id.
-- Nexa Pay, Nexa Go rider, and Nexa Stays guest share a single CONSUMER per identity.
-- See: backend/docs/consumer-data-ownership.md
--
-- If migration fails with unique violation:
--   SELECT phone_number, unified_identity_id, count(*) FROM users
--   WHERE account_type = 'CONSUMER' GROUP BY 1, 2 HAVING count(*) > 1;
--   Resolve duplicates (merge/delete) before re-running.

-- 1. One CONSUMER per unified_identity (when identity is set)
CREATE UNIQUE INDEX IF NOT EXISTS uniq_consumer_per_unified_identity
  ON users(unified_identity_id)
  WHERE account_type = 'CONSUMER' AND unified_identity_id IS NOT NULL;

-- 2. One CONSUMER per phone (defense in depth; catches duplicates before identity linking)
CREATE UNIQUE INDEX IF NOT EXISTS uniq_consumer_per_phone
  ON users(phone_number)
  WHERE account_type = 'CONSUMER';

COMMENT ON INDEX uniq_consumer_per_unified_identity IS 'One CONSUMER account per UnifiedIdentity; shared across Pay, Go rider, Stays guest';
COMMENT ON INDEX uniq_consumer_per_phone IS 'One CONSUMER per phone; prevents duplicate consumer creation';
