-- Support tickets + canonical report/safety records
-- Ticket numbers: SUP-{YYYY}-{NNNNNN}
-- Ticket always owns a SUPPORT conversation (conversation_id UNIQUE NOT NULL)

BEGIN;

CREATE TABLE IF NOT EXISTS stays_support_ticket_ref_counters (
  year INT PRIMARY KEY,
  counter BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS stays_conversation_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES stays_conversations(id) ON DELETE CASCADE,
  reporter_user_id VARCHAR(128) NOT NULL,
  reason TEXT,
  attachment_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  status VARCHAR(32) NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'reviewed', 'dismissed', 'escalated')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_conversation_reports_created
  ON stays_conversation_reports (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stays_conversation_reports_conversation
  ON stays_conversation_reports (conversation_id);
CREATE INDEX IF NOT EXISTS idx_stays_conversation_reports_reporter
  ON stays_conversation_reports (reporter_user_id);

CREATE TABLE IF NOT EXISTS stays_safety_issues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES stays_conversations(id) ON DELETE CASCADE,
  reporter_user_id VARCHAR(128) NOT NULL,
  category VARCHAR(40) NOT NULL
    CHECK (category IN (
      'FEEL_UNSAFE',
      'SUSPICIOUS_FRAUDULENT',
      'PROPERTY_PROBLEM',
      'THREATS_HARASSMENT',
      'OTHER'
    )),
  details TEXT,
  attachment_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  status VARCHAR(32) NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'reviewed', 'dismissed', 'escalated')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_safety_issues_created
  ON stays_safety_issues (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stays_safety_issues_conversation
  ON stays_safety_issues (conversation_id);
CREATE INDEX IF NOT EXISTS idx_stays_safety_issues_reporter
  ON stays_safety_issues (reporter_user_id);

CREATE TABLE IF NOT EXISTS stays_support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_number VARCHAR(32) NOT NULL,
  requester_user_id VARCHAR(128) NOT NULL,
  party VARCHAR(10) NOT NULL
    CHECK (party IN ('GUEST', 'HOST')),
  category VARCHAR(32) NOT NULL
    CHECK (category IN (
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
    )),
  subject TEXT NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'OPEN'
    CHECK (status IN (
      'OPEN',
      'IN_PROGRESS',
      'WAITING_FOR_CUSTOMER',
      'WAITING_FOR_HOST',
      'ESCALATED',
      'RESOLVED',
      'CLOSED'
    )),
  priority VARCHAR(16) NOT NULL DEFAULT 'NORMAL'
    CHECK (priority IN ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
  assigned_admin_id VARCHAR(128),
  conversation_id UUID NOT NULL UNIQUE
    REFERENCES stays_conversations(id),
  booking_id UUID REFERENCES stays_bookings(id) ON DELETE SET NULL,
  listing_id UUID REFERENCES stays_listings(id) ON DELETE SET NULL,
  report_id UUID REFERENCES stays_conversation_reports(id) ON DELETE SET NULL,
  safety_issue_id UUID REFERENCES stays_safety_issues(id) ON DELETE SET NULL,
  unread_for_support BOOLEAN NOT NULL DEFAULT TRUE,
  last_message_preview TEXT,
  customer_name VARCHAR(256),
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_stays_support_tickets_ticket_number
  ON stays_support_tickets (ticket_number);
CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_queue
  ON stays_support_tickets (status, priority, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_requester
  ON stays_support_tickets (requester_user_id);
CREATE INDEX IF NOT EXISTS idx_stays_support_tickets_unread
  ON stays_support_tickets (unread_for_support)
  WHERE unread_for_support = TRUE;

COMMIT;
