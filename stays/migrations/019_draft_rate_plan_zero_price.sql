-- Allow placeholder pricing on DRAFT listings (price required at submit).
ALTER TABLE stays_rate_plans
  DROP CONSTRAINT IF EXISTS stays_rate_plans_base_price_check;

ALTER TABLE stays_rate_plans
  ADD CONSTRAINT stays_rate_plans_base_price_check CHECK (base_price >= 0);
