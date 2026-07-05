-- Align remaining Identity SSO entity columns (audit + kyc admin overrides)

ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS admin_user_id UUID NULL;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS admin_email VARCHAR(150) NULL;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS entity_type VARCHAR(50) NULL;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS entity_id VARCHAR(100) NULL;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS ip_address VARCHAR(60) NULL;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS device_id VARCHAR(100) NULL;

ALTER TABLE kyc_admin_overrides
  ADD COLUMN IF NOT EXISTS bypass_limits_maker_version SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE kyc_admin_overrides
  ADD COLUMN IF NOT EXISTS bypass_limits_second_approver_admin_id UUID NULL;
ALTER TABLE kyc_admin_overrides
  ADD COLUMN IF NOT EXISTS boost_daily_withdrawal_mad NUMERIC(18, 2) NOT NULL DEFAULT 0;
ALTER TABLE kyc_admin_overrides
  ADD COLUMN IF NOT EXISTS boost_monthly_withdrawal_mad NUMERIC(18, 2) NOT NULL DEFAULT 0;
