-- Human-friendly booking references for host support / CSV export
-- Format: NST-{YYYY}-{NNNNNN} (yearly sequence)

CREATE TABLE IF NOT EXISTS stays_booking_ref_counters (
  year INT PRIMARY KEY,
  last_seq INT NOT NULL DEFAULT 0
);

ALTER TABLE stays_bookings
  ADD COLUMN IF NOT EXISTS booking_reference VARCHAR(32);

-- Backfill existing rows ordered by created_at (per UTC year)
WITH ordered AS (
  SELECT
    id,
    EXTRACT(YEAR FROM created_at AT TIME ZONE 'UTC')::INT AS y,
    ROW_NUMBER() OVER (
      PARTITION BY EXTRACT(YEAR FROM created_at AT TIME ZONE 'UTC')
      ORDER BY created_at ASC, id ASC
    ) AS seq
  FROM stays_bookings
  WHERE booking_reference IS NULL
)
UPDATE stays_bookings b
SET booking_reference = 'NST-' || o.y::TEXT || '-' || LPAD(o.seq::TEXT, 6, '0')
FROM ordered o
WHERE b.id = o.id;

INSERT INTO stays_booking_ref_counters (year, last_seq)
SELECT
  EXTRACT(YEAR FROM created_at AT TIME ZONE 'UTC')::INT AS y,
  MAX(
    NULLIF(
      REGEXP_REPLACE(booking_reference, '^NST-[0-9]{4}-', ''),
      ''
    )::INT
  ) AS last_seq
FROM stays_bookings
WHERE booking_reference IS NOT NULL
  AND booking_reference ~ '^NST-[0-9]{4}-[0-9]{6}$'
GROUP BY EXTRACT(YEAR FROM created_at AT TIME ZONE 'UTC')::INT
ON CONFLICT (year) DO UPDATE
SET last_seq = GREATEST(stays_booking_ref_counters.last_seq, EXCLUDED.last_seq);

ALTER TABLE stays_bookings
  ALTER COLUMN booking_reference SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_stays_bookings_booking_reference
  ON stays_bookings (booking_reference);
