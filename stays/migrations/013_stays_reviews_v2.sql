-- Extend guest review system: moderation, media, half-star ratings, listing histogram.

-- Upgrade rating to half-star increments
ALTER TABLE stays_listing_reviews
  ALTER COLUMN rating TYPE NUMERIC(2, 1) USING rating::NUMERIC(2, 1);

ALTER TABLE stays_listing_reviews
  DROP CONSTRAINT IF EXISTS stays_listing_reviews_rating_check;

ALTER TABLE stays_listing_reviews
  ADD CONSTRAINT stays_listing_reviews_rating_check
  CHECK (
    rating IN (0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5)
  );

ALTER TABLE stays_listing_reviews
  ADD COLUMN IF NOT EXISTS host_user_id UUID;

ALTER TABLE stays_listing_reviews
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'PUBLISHED';

ALTER TABLE stays_listing_reviews
  ADD CONSTRAINT stays_listing_reviews_status_check
  CHECK (status IN ('PUBLISHED', 'HIDDEN', 'REMOVED'));

ALTER TABLE stays_listing_reviews
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE stays_listing_reviews
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_stays_listing_reviews_status
  ON stays_listing_reviews (listing_id, status);

CREATE INDEX IF NOT EXISTS idx_stays_listing_reviews_booking
  ON stays_listing_reviews (booking_id);

-- Review media (references Media Service asset IDs)
CREATE TABLE IF NOT EXISTS stays_review_media (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id UUID NOT NULL REFERENCES stays_listing_reviews(id) ON DELETE CASCADE,
  asset_id UUID NOT NULL,
  display_order SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stays_review_media_review
  ON stays_review_media (review_id, display_order);

-- Listing rating histogram (precomputed)
ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS ratings_1 INT NOT NULL DEFAULT 0;

ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS ratings_2 INT NOT NULL DEFAULT 0;

ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS ratings_3 INT NOT NULL DEFAULT 0;

ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS ratings_4 INT NOT NULL DEFAULT 0;

ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS ratings_5 INT NOT NULL DEFAULT 0;

COMMENT ON TABLE stays_review_media IS 'Review photo attachments — asset_id from Media Service';
