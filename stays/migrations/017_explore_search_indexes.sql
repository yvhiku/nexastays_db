-- Explore search: keyset + rating indexes for LIVE listings
-- Supports cursor pagination and sort=newest|rating without full catalog scans.

CREATE INDEX IF NOT EXISTS idx_stays_listings_live_created
  ON stays_listings (created_at DESC, id DESC)
  WHERE status = 'LIVE';

CREATE INDEX IF NOT EXISTS idx_stays_listings_live_rating
  ON stays_listings (
    avg_rating DESC NULLS LAST,
    review_count DESC,
    created_at DESC,
    id DESC
  )
  WHERE status = 'LIVE';

CREATE INDEX IF NOT EXISTS idx_stays_listings_city_lower
  ON stays_listings (LOWER(city));
