-- Support & Trust Phase 3 — canned replies (soft deactivate)

BEGIN;

CREATE TABLE IF NOT EXISTS stays_support_canned_replies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(120) NOT NULL,
  body TEXT NOT NULL,
  category VARCHAR(32) NULL,
  created_by_admin_id VARCHAR(128) NOT NULL,
  updated_by_admin_id VARCHAR(128) NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  CONSTRAINT stays_support_canned_replies_title_len
    CHECK (char_length(title) >= 1 AND char_length(title) <= 120),
  CONSTRAINT stays_support_canned_replies_body_len
    CHECK (char_length(body) >= 1 AND char_length(body) <= 5000)
);

CREATE INDEX IF NOT EXISTS idx_stays_support_canned_replies_active
  ON stays_support_canned_replies (is_active, updated_at DESC);

COMMIT;
