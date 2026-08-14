-- Staff RBAC: ADMIN (Super Admin) vs SUPPORT_AGENT.
-- Independent of product account_type (CONSUMER/HOST/ADMIN/…). Existing rows default to ADMIN.
ALTER TABLE users
ADD COLUMN IF NOT EXISTS staff_role VARCHAR(32) NOT NULL DEFAULT 'ADMIN';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_staff_role') THEN
    ALTER TABLE users DROP CONSTRAINT chk_users_staff_role;
  END IF;
  ALTER TABLE users ADD CONSTRAINT chk_users_staff_role
    CHECK (staff_role IN ('ADMIN', 'SUPPORT_AGENT'));
END $$;

COMMENT ON COLUMN users.staff_role IS
  'Dashboard staff authorization: ADMIN (Super Admin) or SUPPORT_AGENT. Requires account_type=ADMIN.';
