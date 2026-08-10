-- SEC-003: authorization version for admin JWT revocation without waiting full access TTL.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS authz_version INTEGER NOT NULL DEFAULT 1;

COMMENT ON COLUMN users.authz_version IS
  'Incremented on admin privilege revocation/freeze/force-logout; compared to JWT claim av';
