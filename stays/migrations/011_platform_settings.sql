-- Platform-wide fee settings (single row, editable from admin dashboard)
CREATE TABLE IF NOT EXISTS stays_platform_settings (
  id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  guest_fee_pct NUMERIC(6, 4) NOT NULL DEFAULT 0.05,
  host_fee_pct NUMERIC(6, 4) NOT NULL DEFAULT 0.05,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID NULL
);

INSERT INTO stays_platform_settings (id, guest_fee_pct, host_fee_pct)
VALUES (1, 0.05, 0.05)
ON CONFLICT (id) DO NOTHING;
