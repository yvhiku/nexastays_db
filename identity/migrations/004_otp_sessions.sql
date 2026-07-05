-- OTP sessions table for secure PIN setup

CREATE TABLE IF NOT EXISTS otp_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number VARCHAR(20) NOT NULL,
    user_id UUID REFERENCES users(id),
    session_token VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    consumed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_otp_sessions_phone_number ON otp_sessions(phone_number);
CREATE INDEX IF NOT EXISTS idx_otp_sessions_session_token ON otp_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_otp_sessions_expires_at ON otp_sessions(expires_at);

INSERT INTO ledger_accounts (wallet_id, system_account, account_type, created_at)
SELECT NULL, TRUE, account_type, NOW()
FROM (VALUES ('SYSTEM_MAIN'), ('SYSTEM_FEES'), ('SYSTEM_REVERSALS')) AS t(account_type)
WHERE NOT EXISTS (
    SELECT 1 FROM ledger_accounts
    WHERE system_account = TRUE AND ledger_accounts.account_type = t.account_type
);
