-- OTP verify lockout: track failed attempts per phone+IP, lock after 5 failures in 15 minutes
CREATE TABLE IF NOT EXISTS otp_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number VARCHAR(20) NOT NULL,
    ip VARCHAR(45) NOT NULL,
    failed_count INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMP NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_otp_attempts_phone_ip ON otp_attempts(phone_number, ip);
CREATE INDEX IF NOT EXISTS idx_otp_attempts_updated_at ON otp_attempts(updated_at);

COMMENT ON TABLE otp_attempts IS 'OTP verify lockout: 5 failed attempts in 15 min locks out phone+IP';
