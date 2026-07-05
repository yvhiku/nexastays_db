-- Extend stays_booking_occupants with phone, email, gender, id document asset IDs
-- Run when not using TypeORM synchronize.

ALTER TABLE stays_booking_occupants
  ADD COLUMN IF NOT EXISTS phone VARCHAR(32),
  ADD COLUMN IF NOT EXISTS email VARCHAR(150),
  ADD COLUMN IF NOT EXISTS gender VARCHAR(20),
  ADD COLUMN IF NOT EXISTS id_document_front_asset_id VARCHAR(128),
  ADD COLUMN IF NOT EXISTS id_document_back_asset_id VARCHAR(128);
