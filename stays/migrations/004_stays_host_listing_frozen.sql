-- Freeze host listing: host can still book but cannot create/update listings until unfrozen.
ALTER TABLE stays_host_profiles
  ADD COLUMN IF NOT EXISTS listing_frozen BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN stays_host_profiles.listing_frozen IS 'When true, host cannot list properties; they can still use the app to book.';
