-- Allow HOSTEL as a listing_type on stays_listings.

DO $$
DECLARE
  con_name text;
BEGIN
  SELECT c.conname INTO con_name
  FROM pg_constraint c
  JOIN pg_class t ON c.conrelid = t.oid
  JOIN pg_namespace n ON t.relnamespace = n.oid
  WHERE t.relname = 'stays_listings'
    AND n.nspname = current_schema()
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%listing_type%';

  IF con_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE stays_listings DROP CONSTRAINT %I', con_name);
  END IF;
END $$;

ALTER TABLE stays_listings
  ADD CONSTRAINT stays_listings_listing_type_check
  CHECK (listing_type IN ('APARTMENT', 'HOTEL', 'RIAD', 'VILLA', 'HOSTEL'));
