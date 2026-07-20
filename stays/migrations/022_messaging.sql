-- Nexa Stays messaging subsystem (production foundation)
BEGIN;

-- Wi-Fi credentials for check-in cards
ALTER TABLE stays_check_in_contacts
  ADD COLUMN IF NOT EXISTS wifi_ssid VARCHAR(128),
  ADD COLUMN IF NOT EXISTS wifi_password VARCHAR(128);

CREATE TABLE IF NOT EXISTS stays_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID UNIQUE REFERENCES stays_bookings(id) ON DELETE CASCADE,
  type VARCHAR(20) NOT NULL DEFAULT 'BOOKING'
    CHECK (type IN ('BOOKING', 'SUPPORT', 'SYSTEM')),
  messaging_state VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
    CHECK (messaging_state IN ('ACTIVE', 'LOCKED', 'READ_ONLY', 'ARCHIVED')),
  guest_visibility VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
    CHECK (guest_visibility IN ('ACTIVE', 'ARCHIVED', 'DELETED')),
  host_visibility VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
    CHECK (host_visibility IN ('ACTIVE', 'ARCHIVED', 'DELETED')),
  conversation_version INT NOT NULL DEFAULT 1,
  snapshot_version INT NOT NULL DEFAULT 1,
  reservation_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  listing_id UUID REFERENCES stays_listings(id) ON DELETE SET NULL,
  host_user_id VARCHAR(128),
  guest_user_id VARCHAR(128),
  last_message_id UUID,
  last_message_sequence BIGINT NOT NULL DEFAULT 0,
  last_message_preview TEXT,
  last_message_at TIMESTAMPTZ,
  guest_last_read_at TIMESTAMPTZ,
  host_last_read_at TIMESTAMPTZ,
  guest_last_read_message_id UUID,
  host_last_read_message_id UUID,
  unread_guest INT NOT NULL DEFAULT 0,
  unread_host INT NOT NULL DEFAULT 0,
  notification_level_guest VARCHAR(20) NOT NULL DEFAULT 'ALL'
    CHECK (notification_level_guest IN ('ALL', 'IMPORTANT', 'MUTED')),
  notification_level_host VARCHAR(20) NOT NULL DEFAULT 'ALL'
    CHECK (notification_level_host IN ('ALL', 'IMPORTANT', 'MUTED')),
  blocked_by_guest BOOLEAN NOT NULL DEFAULT FALSE,
  blocked_by_host BOOLEAN NOT NULL DEFAULT FALSE,
  locked_at TIMESTAMPTZ,
  read_only_at TIMESTAMPTZ,
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_conversations_guest_inbox
  ON stays_conversations (guest_user_id, unread_guest DESC, last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_stays_conversations_host_inbox
  ON stays_conversations (host_user_id, unread_host DESC, last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_stays_conversations_messaging_state
  ON stays_conversations (messaging_state);

CREATE TABLE IF NOT EXISTS stays_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES stays_conversations(id) ON DELETE CASCADE,
  conversation_sequence BIGINT NOT NULL,
  sender_id VARCHAR(128),
  type VARCHAR(30) NOT NULL
    CHECK (type IN (
      'TEXT', 'SYSTEM_EVENT', 'SYSTEM_NOTICE', 'SYSTEM_INTERNAL',
      'PROPERTY_CARD', 'BOOKING_CARD', 'CHECKIN_CARD', 'WIFI_CARD',
      'LOCATION_CARD', 'REVIEW_CARD', 'PAYMENT_CARD', 'IMAGE', 'FILE'
    )),
  body TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  status VARCHAR(20) NOT NULL DEFAULT 'PERSISTED'
    CHECK (status IN ('PENDING', 'PERSISTED', 'DELIVERED', 'READ', 'FAILED')),
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  pushed_at TIMESTAMPTZ,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  client_message_id UUID,
  client_created_at TIMESTAMPTZ,
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  deleted_by VARCHAR(128),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (conversation_id, conversation_sequence),
  UNIQUE (conversation_id, client_message_id)
);

CREATE INDEX IF NOT EXISTS idx_stays_messages_conversation_seq
  ON stays_messages (conversation_id, conversation_sequence ASC);
CREATE INDEX IF NOT EXISTS idx_stays_messages_body_fts
  ON stays_messages USING GIN (to_tsvector('simple', COALESCE(body, '')));

CREATE TABLE IF NOT EXISTS stays_message_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES stays_messages(id) ON DELETE CASCADE,
  storage_url TEXT NOT NULL,
  thumbnail_url TEXT,
  mime VARCHAR(128),
  width INT,
  height INT,
  blurhash VARCHAR(64),
  virus_scan_status VARCHAR(20) DEFAULT 'PENDING',
  size_bytes BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_message_attachments_message
  ON stays_message_attachments (message_id);

CREATE TABLE IF NOT EXISTS stays_messaging_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type VARCHAR(64) NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'PROCESSING', 'DONE', 'FAILED')),
  attempts INT NOT NULL DEFAULT 0,
  next_retry_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_stays_messaging_outbox_pending
  ON stays_messaging_outbox (status, next_retry_at)
  WHERE status IN ('PENDING', 'FAILED');

CREATE TABLE IF NOT EXISTS stays_messaging_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES stays_conversations(id) ON DELETE SET NULL,
  actor_user_id VARCHAR(128),
  action VARCHAR(64) NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_messaging_audit_conversation
  ON stays_messaging_audit_log (conversation_id, created_at DESC);

ALTER TABLE stays_conversations
  ADD CONSTRAINT fk_stays_conversations_last_message
  FOREIGN KEY (last_message_id) REFERENCES stays_messages(id) ON DELETE SET NULL;

COMMIT;
