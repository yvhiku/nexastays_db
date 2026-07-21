-- Merge duplicate booking conversations, archive completed stay threads, enforce one thread per booking.
-- Safe to re-run: skips when no duplicates remain.

DO $$
DECLARE
  r RECORD;
  keep_id uuid;
  drop_id uuid;
  max_seq int;
  last_msg RECORD;
BEGIN
  FOR r IN
    SELECT booking_id, array_agg(id ORDER BY created_at ASC) AS conv_ids
    FROM stays_conversations
    WHERE booking_id IS NOT NULL
    GROUP BY booking_id
    HAVING COUNT(*) > 1
  LOOP
    keep_id := r.conv_ids[1];

    FOR i IN 2..array_length(r.conv_ids, 1) LOOP
      drop_id := r.conv_ids[i];

      SELECT COALESCE(MAX(conversation_sequence), 0)
      INTO max_seq
      FROM stays_messages
      WHERE conversation_id = keep_id;

      UPDATE stays_messages sm
      SET conversation_id = keep_id,
          conversation_sequence = max_seq + sub.rn
      FROM (
        SELECT id, ROW_NUMBER() OVER (ORDER BY conversation_sequence ASC) AS rn
        FROM stays_messages
        WHERE conversation_id = drop_id
      ) sub
      WHERE sm.id = sub.id;

      DELETE FROM stays_conversations WHERE id = drop_id;
    END LOOP;

    SELECT m.id, m.conversation_sequence, m.created_at, m.type, m.body
    INTO last_msg
    FROM stays_messages m
    WHERE m.conversation_id = keep_id
      AND m.deleted_at IS NULL
    ORDER BY m.conversation_sequence DESC
    LIMIT 1;

    IF FOUND THEN
      UPDATE stays_conversations
      SET last_message_id = last_msg.id,
          last_message_sequence = last_msg.conversation_sequence,
          last_message_preview = COALESCE(NULLIF(TRIM(last_msg.body), ''), last_message_preview),
          last_message_at = last_msg.created_at,
          updated_at = NOW()
      WHERE id = keep_id;
    END IF;
  END LOOP;
END $$;

UPDATE stays_conversations c
SET messaging_state = 'ARCHIVED',
    guest_visibility = 'ARCHIVED',
    host_visibility = 'ARCHIVED',
    archived_at = COALESCE(c.archived_at, NOW()),
    read_only_at = COALESCE(c.read_only_at, NOW()),
    updated_at = NOW()
FROM stays_bookings b
WHERE c.booking_id = b.id
  AND b.status = 'COMPLETED'
  AND c.messaging_state <> 'ARCHIVED';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'stays_conversations_booking_id_key'
  ) THEN
    ALTER TABLE stays_conversations
      ADD CONSTRAINT stays_conversations_booking_id_key UNIQUE (booking_id);
  END IF;
EXCEPTION
  WHEN duplicate_table OR unique_violation OR duplicate_object THEN
    RAISE NOTICE 'stays_conversations_booking_id_key already present or duplicate booking_id remains; skipped';
END $$;
