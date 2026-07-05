-- Check-in access instructions (key box code, meet-up details, etc.)
ALTER TABLE stays_check_in_contacts
  ADD COLUMN IF NOT EXISTS access_instructions TEXT;
