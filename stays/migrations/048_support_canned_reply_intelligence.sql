-- Loop 3: canned-reply language + ticket-category targeting (GENERAL = NULL)

BEGIN;

UPDATE stays_support_canned_replies
SET category = NULL
WHERE category IS NOT NULL
  AND category NOT IN (
    'BOOKING',
    'PAYMENT',
    'REFUND',
    'CANCELLATION',
    'HOST',
    'GUEST',
    'LISTING',
    'KYC',
    'TECHNICAL',
    'FRAUD',
    'OTHER'
  );

ALTER TABLE stays_support_canned_replies
  ADD COLUMN IF NOT EXISTS language VARCHAR(10) NULL;

ALTER TABLE stays_support_canned_replies
  DROP CONSTRAINT IF EXISTS stays_support_canned_replies_language_check;

ALTER TABLE stays_support_canned_replies
  ADD CONSTRAINT stays_support_canned_replies_language_check
  CHECK (
    language IS NULL
    OR language IN ('ar', 'fr', 'en')
  );

ALTER TABLE stays_support_canned_replies
  DROP CONSTRAINT IF EXISTS stays_support_canned_replies_category_check;

ALTER TABLE stays_support_canned_replies
  ADD CONSTRAINT stays_support_canned_replies_category_check
  CHECK (
    category IS NULL
    OR category IN (
      'BOOKING',
      'PAYMENT',
      'REFUND',
      'CANCELLATION',
      'HOST',
      'GUEST',
      'LISTING',
      'KYC',
      'TECHNICAL',
      'FRAUD',
      'OTHER'
    )
  );

CREATE INDEX IF NOT EXISTS idx_stays_support_canned_replies_discover
  ON stays_support_canned_replies (is_active, category, language);

COMMIT;
