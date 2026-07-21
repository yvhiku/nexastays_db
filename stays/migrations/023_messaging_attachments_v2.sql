-- First-class messaging attachments (upload before message)

ALTER TABLE stays_message_attachments
  ALTER COLUMN message_id DROP NOT NULL;

ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS conversation_id UUID REFERENCES stays_conversations(id) ON DELETE CASCADE;

ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS uploader_user_id UUID;

ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'PROCESSING'
    CHECK (status IN ('PROCESSING', 'READY', 'FAILED'));

ALTER TABLE stays_message_attachments
  ADD COLUMN IF NOT EXISTS original_filename TEXT;

CREATE INDEX IF NOT EXISTS idx_stays_message_attachments_conversation
  ON stays_message_attachments (conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_stays_message_attachments_status
  ON stays_message_attachments (status)
  WHERE message_id IS NULL;
