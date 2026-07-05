-- Add email column for admin login and user profiles

ALTER TABLE users ADD COLUMN IF NOT EXISTS email VARCHAR(150) NULL;
