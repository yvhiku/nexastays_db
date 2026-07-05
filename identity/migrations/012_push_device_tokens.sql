-- FCM device tokens bound to user + device.
CREATE TABLE IF NOT EXISTS push_device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    device_id VARCHAR(120) NOT NULL,
    token VARCHAR(512) NOT NULL,
    platform VARCHAR(20) NOT NULL DEFAULT 'unknown',
    notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    last_seen_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_push_device_tokens_user
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_push_device_tokens_user_device
  ON push_device_tokens(user_id, device_id);
CREATE INDEX IF NOT EXISTS idx_push_device_tokens_user
  ON push_device_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_push_device_tokens_active
  ON push_device_tokens(active);
