-- Guest reviews for stays listings (one review per completed stay / booking).

CREATE TABLE IF NOT EXISTS stays_listing_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES stays_listings(id) ON DELETE CASCADE,
  booking_id UUID NOT NULL UNIQUE REFERENCES stays_bookings(id) ON DELETE CASCADE,
  guest_user_id UUID NOT NULL,
  rating SMALLINT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stays_listing_reviews_listing_created
  ON stays_listing_reviews (listing_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_stays_listing_reviews_guest
  ON stays_listing_reviews (guest_user_id);

ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS avg_rating DECIMAL(4, 2);

ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS review_count INT NOT NULL DEFAULT 0;

COMMENT ON TABLE stays_listing_reviews IS 'Public guest reviews tied to a stay booking';
