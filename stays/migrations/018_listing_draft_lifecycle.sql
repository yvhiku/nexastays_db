-- Listing UX create-early: draft lifecycle + last edit tracking
ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS last_edited_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ NULL;

CREATE INDEX IF NOT EXISTS idx_stays_listings_draft_lifecycle
  ON stays_listings (status, last_edited_at)
  WHERE status = 'DRAFT' AND archived_at IS NULL;
