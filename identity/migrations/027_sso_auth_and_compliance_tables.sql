-- SSO auth + compliance tables missing from early identity migrations (were TypeORM-synced on monolith)

CREATE TABLE IF NOT EXISTS otp_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number VARCHAR(20) NOT NULL,
  code VARCHAR(10) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  attempts INT NOT NULL DEFAULT 0,
  consumed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_otp_codes_phone_number ON otp_codes (phone_number);

CREATE TABLE IF NOT EXISTS security_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NULL REFERENCES users(id) ON DELETE SET NULL,
  event_type VARCHAR(40) NOT NULL,
  metadata JSONB NULL,
  ip_address VARCHAR(60) NULL,
  device_id VARCHAR(120) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_security_events_user_created_at
  ON security_events (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_security_events_type_created_at
  ON security_events (event_type, created_at);

CREATE TABLE IF NOT EXISTS risk_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type VARCHAR(30) NOT NULL,
  severity VARCHAR(10) NOT NULL,
  user_id UUID NULL REFERENCES users(id) ON DELETE SET NULL,
  transaction_id UUID NULL,
  amount NUMERIC(18, 2) NULL,
  transaction_reference VARCHAR(100) NULL,
  description TEXT NOT NULL,
  risk_score INT NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sar_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  transaction_id UUID NULL,
  risk_reason VARCHAR(120) NOT NULL,
  risk_score INT NOT NULL,
  device_context JSONB NULL,
  report_payload JSONB NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fraud_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  transaction_type VARCHAR(30) NOT NULL,
  amount NUMERIC(18, 2) NOT NULL,
  risk_score INT NOT NULL,
  reason_code VARCHAR(80) NOT NULL,
  severity VARCHAR(10) NOT NULL,
  action VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
  assigned_owner VARCHAR(120) NULL,
  internal_note TEXT NULL,
  metadata JSONB NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
