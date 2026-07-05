-- Device binding table: trusted devices per user/account.
CREATE TABLE IF NOT EXISTS trusted_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    device_id VARCHAR(120) NOT NULL,
    device_name VARCHAR(120) NULL,
    trusted BOOLEAN NOT NULL DEFAULT FALSE,
    first_seen_at TIMESTAMPTZ NULL,
    last_seen_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_trusted_devices_user
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_trusted_devices_user_device
  ON trusted_devices(user_id, device_id);
CREATE INDEX IF NOT EXISTS idx_trusted_devices_user
  ON trusted_devices(user_id);
CREATE INDEX IF NOT EXISTS idx_trusted_devices_last_seen
  ON trusted_devices(last_seen_at);

COMMENT ON TABLE trusted_devices IS 'Trusted device bindings per account';
