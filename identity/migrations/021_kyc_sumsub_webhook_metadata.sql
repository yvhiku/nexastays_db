BEGIN;

ALTER TABLE kyc_profiles
  ADD COLUMN IF NOT EXISTS last_webhook_event_type VARCHAR(100) NULL,
  ADD COLUMN IF NOT EXISTS last_webhook_received_at TIMESTAMP NULL;

COMMIT;
