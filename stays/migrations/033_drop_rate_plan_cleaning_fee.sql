-- Permanently remove cleaning fees from Nexa Stays product pricing.
-- Catalog-only column on stays_rate_plans (never stored on bookings).
-- Historical booking totals remain unchanged (bookings never had cleaning_fee columns).

ALTER TABLE stays_rate_plans
  DROP COLUMN IF EXISTS cleaning_fee;
