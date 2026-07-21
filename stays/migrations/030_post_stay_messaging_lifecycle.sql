-- Post-stay grace period before auto-archive; future-proof archive metadata.
BEGIN;

ALTER TABLE stays_conversations
  ADD COLUMN IF NOT EXISTS post_stay_ends_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS auto_archive_disabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS auto_archive_disabled_reason VARCHAR(32) NULL,
  ADD COLUMN IF NOT EXISTS archive_reason VARCHAR(20) NULL;

CREATE INDEX IF NOT EXISTS idx_stays_conversations_post_stay_ends_at
  ON stays_conversations (post_stay_ends_at)
  WHERE post_stay_ends_at IS NOT NULL AND messaging_state = 'ACTIVE';

-- Repair: completed bookings wrongly archived within grace (default 72h).
DO $$
DECLARE
  grace_hours INT := 72;
  r RECORD;
  checkout_ts TIMESTAMPTZ;
  ends_at TIMESTAMPTZ;
BEGIN
  FOR r IN
    SELECT c.id AS conv_id,
           b.id AS booking_id,
           b.completed_at,
           b.checkout_date,
           COALESCE(l.checkout_time, '11:00') AS checkout_time
    FROM stays_conversations c
    JOIN stays_bookings b ON b.id = c.booking_id
    LEFT JOIN stays_listings l ON l.id = b.listing_id
    WHERE b.status = 'COMPLETED'
      AND c.messaging_state = 'ARCHIVED'
      AND c.type = 'BOOKING'
  LOOP
    IF r.completed_at IS NOT NULL THEN
      checkout_ts := r.completed_at;
    ELSE
      checkout_ts := (r.checkout_date::text || ' ' ||
        split_part(COALESCE(r.checkout_time::text, '11:00'), ':', 1) || ':' ||
        COALESCE(NULLIF(split_part(COALESCE(r.checkout_time::text, '11:00'), ':', 2), ''), '00') || ':00')::timestamptz;
    END IF;

    ends_at := checkout_ts + (grace_hours || ' hours')::interval;

    IF ends_at > NOW() THEN
      UPDATE stays_conversations
      SET messaging_state = 'ACTIVE',
          guest_visibility = 'ACTIVE',
          host_visibility = 'ACTIVE',
          post_stay_ends_at = ends_at,
          archived_at = NULL,
          read_only_at = NULL,
          archive_reason = NULL,
          updated_at = NOW()
      WHERE id = r.conv_id;
    ELSE
      UPDATE stays_conversations
      SET archive_reason = COALESCE(archive_reason, 'AUTO'),
          post_stay_ends_at = COALESCE(post_stay_ends_at, ends_at)
      WHERE id = r.conv_id;
    END IF;
  END LOOP;

  -- Active post-stay rows missing deadline.
  UPDATE stays_conversations c
  SET post_stay_ends_at = sub.ends_at,
      updated_at = NOW()
  FROM (
    SELECT c2.id,
           COALESCE(
             b.completed_at,
             (b.checkout_date::text || ' ' || split_part(COALESCE(l.checkout_time::text, '11:00'), ':', 1) || ':' ||
               COALESCE(NULLIF(split_part(COALESCE(l.checkout_time::text, '11:00'), ':', 2), ''), '00') || ':00')::timestamptz
           ) + (grace_hours || ' hours')::interval AS ends_at
    FROM stays_conversations c2
    JOIN stays_bookings b ON b.id = c2.booking_id
    LEFT JOIN stays_listings l ON l.id = b.listing_id
    WHERE b.status = 'COMPLETED'
      AND c2.messaging_state = 'ACTIVE'
      AND c2.post_stay_ends_at IS NULL
  ) sub
  WHERE c.id = sub.id;
END $$;

COMMIT;
