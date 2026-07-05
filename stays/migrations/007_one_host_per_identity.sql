-- One host profile per Identity account (user_id is JWT sub, already UNIQUE on stays_host_profiles)

COMMENT ON COLUMN stays_host_profiles.user_id IS
  'Identity account id (JWT sub). At most one host profile per account.';
