-- Messaging platform foundation: media assets, attachment sessions, expanded enums

BEGIN;

-- ---------------------------------------------------------------------------
-- Media assets (storage layer — reusable across chat, reviews, listings, etc.)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stays_media_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  storage_key TEXT NOT NULL,
  checksum_sha256 VARCHAR(64),
  mime VARCHAR(128),
  size_bytes BIGINT,
  width INT,
  height INT,
  duration_ms INT,
  orientation INT,
  thumbnail_storage_key TEXT,
  encryption_key_id UUID,
  media_version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_media_assets_checksum
  ON stays_media_assets (checksum_sha256)
  WHERE checksum_sha256 IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Attachment sessions (upload lifecycle before message send)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stays_attachment_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES stays_conversations(id) ON DELETE CASCADE,
  owner_user_id VARCHAR(128) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'CREATED'
    CHECK (status IN ('CREATED', 'UPLOADING', 'READY', 'COMPLETED', 'ABANDONED')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_attachment_sessions_conversation
  ON stays_attachment_sessions (conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_stays_attachment_sessions_orphan_cleanup
  ON stays_attachment_sessions (status, expires_at)
  WHERE status IN ('CREATED', 'UPLOADING', 'READY', 'ABANDONED');

-- ---------------------------------------------------------------------------
-- Conversation attachment version (incremental media sync)
-- ---------------------------------------------------------------------------
ALTER TABLE stays_conversations
  ADD COLUMN IF NOT EXISTS attachment_version INT NOT NULL DEFAULT 1;

-- ---------------------------------------------------------------------------
-- Extend message attachments
-- ---------------------------------------------------------------------------
ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS session_id UUID REFERENCES stays_attachment_sessions(id) ON DELETE SET NULL;

ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS media_asset_id UUID REFERENCES stays_media_assets(id) ON DELETE SET NULL;

ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS media_version INT NOT NULL DEFAULT 1;

ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS orientation INT;

ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS duration_ms INT;

ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS checksum_sha256 VARCHAR(64);

CREATE INDEX IF NOT EXISTS idx_stays_message_attachments_session
  ON stays_message_attachments (session_id)
  WHERE session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_stays_message_attachments_orphan_cleanup
  ON stays_message_attachments (created_at)
  WHERE message_id IS NULL;

-- Normalize virus scan status naming (CLEAN -> SAFE)
UPDATE stays_message_attachments
  SET virus_scan_status = 'SAFE'
  WHERE virus_scan_status IN ('CLEAN', 'OK');

-- ---------------------------------------------------------------------------
-- Expand message type enum (future-proof; existing rows unchanged)
-- ---------------------------------------------------------------------------
ALTER TABLE stays_messages DROP CONSTRAINT IF EXISTS stays_messages_type_check;

ALTER TABLE stays_messages ADD CONSTRAINT stays_messages_type_check
  CHECK (type IN (
    'TEXT', 'SYSTEM_EVENT', 'SYSTEM_NOTICE', 'SYSTEM_INTERNAL',
    'PROPERTY_CARD', 'BOOKING_CARD', 'CHECKIN_CARD', 'WIFI_CARD',
    'LOCATION_CARD', 'REVIEW_CARD', 'PAYMENT_CARD',
    'IMAGE', 'FILE', 'VIDEO', 'VOICE', 'LOCATION', 'SYSTEM', 'CARD', 'CUSTOM'
  ));

-- Normalize attachment processing status constraint (add UPLOADING)
ALTER TABLE stays_message_attachments DROP CONSTRAINT IF EXISTS stays_message_attachments_status_check;

ALTER TABLE stays_message_attachments ADD CONSTRAINT stays_message_attachments_status_check
  CHECK (status IN ('UPLOADING', 'PROCESSING', 'READY', 'FAILED'));

ALTER TABLE stays_message_attachments ALTER COLUMN status SET DEFAULT 'UPLOADING';

COMMIT;
