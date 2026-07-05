-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

BEGIN;

-- =========================
-- USERS
-- =========================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100),
    pin_hash TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- WALLETS
-- =========================
CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id),
    currency CHAR(3) NOT NULL DEFAULT 'MAD',
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- LEDGER ACCOUNTS
-- =========================
CREATE TABLE ledger_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID REFERENCES wallets(id),
    system_account BOOLEAN NOT NULL DEFAULT FALSE,
    account_type VARCHAR(30) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- LEDGER TRANSACTIONS
-- =========================
CREATE TABLE ledger_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reference VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- LEDGER ENTRIES
-- =========================
CREATE TABLE ledger_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES ledger_transactions(id),
    account_id UUID NOT NULL REFERENCES ledger_accounts(id),
    amount NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    entry_type VARCHAR(6) NOT NULL CHECK (entry_type IN ('DEBIT', 'CREDIT')),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- APP TRANSACTIONS
-- =========================
CREATE TABLE app_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_user_id UUID REFERENCES users(id),
    receiver_user_id UUID REFERENCES users(id),
    amount NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    type VARCHAR(30) NOT NULL,
    status VARCHAR(20) NOT NULL,
    reference VARCHAR(64) UNIQUE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- TRANSACTION FEES
-- =========================
CREATE TABLE transaction_fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    app_transaction_id UUID NOT NULL REFERENCES app_transactions(id),
    amount NUMERIC(18,2) NOT NULL CHECK (amount >= 0),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- KYC PROFILES
-- =========================
CREATE TABLE kyc_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id),
    level VARCHAR(20) NOT NULL DEFAULT 'NONE',
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    provider VARCHAR(30),
    reference VARCHAR(100),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- TRANSACTION LIMITS
-- =========================
CREATE TABLE transaction_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kyc_level VARCHAR(20) NOT NULL,
    daily_limit NUMERIC(18,2),
    monthly_limit NUMERIC(18,2)
);

-- =========================
-- IDEMPOTENCY KEYS
-- =========================
CREATE TABLE idempotency_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR(64) UNIQUE NOT NULL,
    user_id UUID REFERENCES users(id),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- AUDIT LOGS
-- =========================
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(50) NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =========================
-- INDEXES
-- =========================
CREATE INDEX idx_users_phone ON users(phone_number);
CREATE INDEX idx_wallets_user ON wallets(user_id);
CREATE INDEX idx_ledger_entries_account ON ledger_entries(account_id);
CREATE INDEX idx_ledger_entries_tx ON ledger_entries(transaction_id);
CREATE INDEX idx_app_tx_users ON app_transactions(sender_user_id, receiver_user_id);
CREATE INDEX idx_app_tx_reference ON app_transactions(reference);

COMMIT;
