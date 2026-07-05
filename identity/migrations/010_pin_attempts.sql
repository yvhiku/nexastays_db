-- PIN verify lockout: track failed attempts per account with exponential backoff
CREATE TABLE IF NOT EXISTS pin_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE,
    failed_count INT NOT NULL DEFAULT 0,
    lockout_level INT NOT NULL DEFAULT 0,
    first_failed_at TIMESTAMP NULL,
    lockout_until TIMESTAMP NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pin_attempts_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_pin_attempts_user_id ON pin_attempts(user_id);
CREATE INDEX IF NOT EXISTS idx_pin_attempts_lockout_until ON pin_attempts(lockout_until);

COMMENT ON TABLE pin_attempts IS 'PIN verify failures per account with exponential lockout backoff';
