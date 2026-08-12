-- Host portal list pagination (cursor/keyset) — indexes justified by EXPLAIN
-- (ANALYZE, BUFFERS) on representative local data (2026-08-12):
--
-- bookings ORDER BY created_at DESC, id DESC via listing.host_user_id:
--   Hash Join + Sort (top-N). Existing idx_stays_bookings_listing alone does not
--   cover created_at/id ordering → add (listing_id, created_at DESC, id DESC).
--
-- listings ORDER BY created_at DESC, id DESC WHERE host_user_id = ?:
--   Seq Scan + Sort at ~1k rows; idx_stays_listings_host exists but does not
--   cover order keys → add (host_user_id, created_at DESC, id DESC).
--
-- Counts queries remain separate; no Redis. Do not add speculative search indexes.

CREATE INDEX IF NOT EXISTS idx_stays_bookings_listing_created_id
  ON stays_bookings (listing_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_stays_listings_host_created_id
  ON stays_listings (host_user_id, created_at DESC, id DESC);
