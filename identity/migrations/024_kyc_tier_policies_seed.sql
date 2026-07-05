-- KYC tier policy table + baseline tiers (NONE, BASIC, STANDARD, FULL).
-- Idempotent: safe to re-run on dev DBs that never applied nexa_backend/database/027.

CREATE TABLE IF NOT EXISTS kyc_tier_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tier_key VARCHAR(32) NOT NULL UNIQUE,
    max_single_transfer_mad NUMERIC(18,2) NOT NULL DEFAULT 0,
    daily_outflow_mad NUMERIC(18,2) NOT NULL DEFAULT 0,
    monthly_outflow_mad NUMERIC(18,2) NOT NULL DEFAULT 0,
    max_wallet_balance_mad NUMERIC(18,2),
    daily_withdrawal_mad NUMERIC(18,2) NOT NULL DEFAULT 0,
    monthly_withdrawal_mad NUMERIC(18,2) NOT NULL DEFAULT 0,
    allowed_country_codes JSONB,
    blocked_country_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
    allowed_receiver_account_types JSONB,
    blocked_merchant_user_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
    velocity_max_completed_outbound INT,
    velocity_window_minutes INT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS kyc_admin_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    bypass_kyc_status_gate BOOLEAN NOT NULL DEFAULT FALSE,
    bypass_all_limits BOOLEAN NOT NULL DEFAULT FALSE,
    boost_daily_outflow_mad NUMERIC(18,2) NOT NULL DEFAULT 0,
    boost_monthly_outflow_mad NUMERIC(18,2) NOT NULL DEFAULT 0,
    boost_max_single_transfer_mad NUMERIC(18,2) NOT NULL DEFAULT 0,
    extra_allowed_country_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
    reason TEXT NOT NULL,
    created_by_admin_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_kyc_admin_overrides_user_active
    ON kyc_admin_overrides (user_id, active)
    WHERE active = TRUE;

INSERT INTO kyc_tier_policies (
    tier_key,
    max_single_transfer_mad,
    daily_outflow_mad,
    monthly_outflow_mad,
    max_wallet_balance_mad,
    daily_withdrawal_mad,
    monthly_withdrawal_mad,
    allowed_country_codes,
    blocked_country_codes,
    allowed_receiver_account_types,
    blocked_merchant_user_ids,
    velocity_max_completed_outbound,
    velocity_window_minutes
) VALUES
(
    'NONE',
    0,
    0,
    0,
    500,
    0,
    0,
    '["MA"]'::jsonb,
    '[]'::jsonb,
    '["CONSUMER"]'::jsonb,
    '[]'::jsonb,
    3,
    60
),
(
    'BASIC',
    2000,
    5000,
    25000,
    20000,
    5000,
    20000,
    '["MA"]'::jsonb,
    '[]'::jsonb,
    '["CONSUMER","MERCHANT"]'::jsonb,
    '[]'::jsonb,
    5,
    60
),
(
    'STANDARD',
    5000,
    10000,
    100000,
    100000,
    10000,
    80000,
    '["MA"]'::jsonb,
    '[]'::jsonb,
    NULL,
    '[]'::jsonb,
    10,
    60
),
(
    'FULL',
    50000,
    50000,
    500000,
    500000,
    50000,
    400000,
    '["MA","FR","ES"]'::jsonb,
    '[]'::jsonb,
    NULL,
    '[]'::jsonb,
    20,
    60
)
ON CONFLICT (tier_key) DO UPDATE SET
    max_single_transfer_mad = EXCLUDED.max_single_transfer_mad,
    daily_outflow_mad = EXCLUDED.daily_outflow_mad,
    monthly_outflow_mad = EXCLUDED.monthly_outflow_mad,
    max_wallet_balance_mad = EXCLUDED.max_wallet_balance_mad,
    daily_withdrawal_mad = EXCLUDED.daily_withdrawal_mad,
    monthly_withdrawal_mad = EXCLUDED.monthly_withdrawal_mad,
    allowed_country_codes = EXCLUDED.allowed_country_codes,
    blocked_country_codes = EXCLUDED.blocked_country_codes,
    allowed_receiver_account_types = EXCLUDED.allowed_receiver_account_types,
    blocked_merchant_user_ids = EXCLUDED.blocked_merchant_user_ids,
    velocity_max_completed_outbound = EXCLUDED.velocity_max_completed_outbound,
    velocity_window_minutes = EXCLUDED.velocity_window_minutes,
    updated_at = NOW();
