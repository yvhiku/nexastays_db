-- Repair orphaned messaging threads when conversation rows were lost but messages remain.
-- Safe to re-run: no-ops when threads already exist.

DO $$
DECLARE
  talia_conv uuid;
  sunny_conv uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM stays_conversations WHERE booking_id = '42f8947a-6090-432a-8428-611dabd518d8'
  ) THEN
    INSERT INTO stays_conversations (
      booking_id, type, listing_id, host_user_id, guest_user_id,
      last_message_id, last_message_sequence, last_message_preview, last_message_at,
      reservation_snapshot
    ) VALUES (
      '42f8947a-6090-432a-8428-611dabd518d8',
      'BOOKING',
      '8568866c-e468-44f5-b099-a1eb2c0f203b',
      '9367ae46-3463-43ed-b39c-c9c68c238e7f',
      '398bcdb4-16c8-42c9-a37a-bb4201a7940f',
      'ab5af04f-ac6e-4a52-8865-81eda5171716',
      19,
      'a',
      '2026-07-21 02:34:04.224207+00',
      '{"listingTitle":"Talia surf taghazout","listingId":"8568866c-e468-44f5-b099-a1eb2c0f203b"}'::jsonb
    )
    RETURNING id INTO talia_conv;

    UPDATE stays_messages
    SET conversation_id = talia_conv
    WHERE conversation_id = 'b9f9f6bf-f2fa-4900-9332-3308494528b5';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM stays_conversations WHERE booking_id = 'fd04ed28-8f49-497b-a3e8-2a828b9ba53f'
  ) THEN
    INSERT INTO stays_conversations (
      booking_id, type, listing_id, host_user_id, guest_user_id,
      last_message_id, last_message_sequence, last_message_preview, last_message_at,
      reservation_snapshot
    ) VALUES (
      'fd04ed28-8f49-497b-a3e8-2a828b9ba53f',
      'BOOKING',
      '3466a54c-8de9-4547-a357-51e2ad90d9bc',
      '9367ae46-3463-43ed-b39c-c9c68c238e7f',
      '398bcdb4-16c8-42c9-a37a-bb4201a7940f',
      '14b1c255-1a6e-4b56-95e8-a1884c5b68b2',
      13,
      'ss',
      '2026-07-21 02:04:34.502245+00',
      '{"listingTitle":"sunny loft on maarif","listingId":"3466a54c-8de9-4547-a357-51e2ad90d9bc"}'::jsonb
    )
    RETURNING id INTO sunny_conv;

    UPDATE stays_messages
    SET conversation_id = sunny_conv
    WHERE conversation_id = 'befef25e-5400-4177-a1ca-37b17a05ac5e';
  END IF;
END $$;

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
    RAISE NOTICE 'stays_conversations_booking_id_key already present or ghost index remains; skipped';
END $$;

REINDEX TABLE stays_conversations;
