-- Host applications history (standalone — applicant_user_id is Identity account UUID)

CREATE TABLE IF NOT EXISTS host_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_user_id UUID NOT NULL,
  phone_number VARCHAR(50) NOT NULL,
  full_name VARCHAR(255),
  email VARCHAR(255),
  status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'UNDER_REVIEW', 'APPROVED', 'REJECTED')),
  rejection_reason TEXT,
  reviewed_at TIMESTAMPTZ,
  reviewed_by VARCHAR(100),
  identity_reused BOOLEAN NOT NULL DEFAULT FALSE,
  hosting_policies_accepted_at TIMESTAMPTZ,
  payout_setup_completed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_host_applications_applicant ON host_applications(applicant_user_id);
CREATE INDEX IF NOT EXISTS idx_host_applications_phone ON host_applications(phone_number);
CREATE INDEX IF NOT EXISTS idx_host_applications_status ON host_applications(status);
CREATE INDEX IF NOT EXISTS idx_host_applications_created ON host_applications(created_at DESC);

COMMENT ON TABLE host_applications IS 'Nexa Stays host application history; Identity owns KYC';
