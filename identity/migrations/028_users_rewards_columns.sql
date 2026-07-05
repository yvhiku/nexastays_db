-- Rewards columns on users (entity expects these; optional for SSO but required for TypeORM queries)

ALTER TABLE users ADD COLUMN IF NOT EXISTS rewards_tier VARCHAR(20) NOT NULL DEFAULT 'standard';
ALTER TABLE users ADD COLUMN IF NOT EXISTS nexa_points INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS rewards_referral_code VARCHAR(32) NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS rewards_kyc_completed BOOLEAN NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_rewards_referral_code
  ON users (rewards_referral_code)
  WHERE rewards_referral_code IS NOT NULL;
