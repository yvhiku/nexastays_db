-- Support & Trust Phase 4 — deterministic operational signals
-- Advisory only: no automatic ticket/message/assignment mutations.

BEGIN;

CREATE TABLE IF NOT EXISTS stays_support_operational_signals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NULL REFERENCES stays_support_tickets (id) ON DELETE CASCADE,
  report_id UUID NULL,
  safety_issue_id UUID NULL,

  signal_type VARCHAR(64) NOT NULL,
  severity VARCHAR(16) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',

  subject_type VARCHAR(64) NOT NULL,
  subject_id VARCHAR(128) NULL,

  rule_version VARCHAR(32) NOT NULL DEFAULT 'v1',
  dedupe_key VARCHAR(160) NOT NULL,

  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

  first_detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  acknowledged_at TIMESTAMPTZ NULL,
  acknowledged_by_admin_id VARCHAR(128) NULL,
  resolved_at TIMESTAMPTZ NULL,
  resolved_by_admin_id VARCHAR(128) NULL,

  CONSTRAINT stays_support_operational_signals_type_check
    CHECK (signal_type IN (
      'REPEAT_REPORT',
      'REPEAT_SAFETY_REPORT',
      'MULTIPLE_OPEN_TICKETS',
      'SLA_ATTENTION',
      'SLA_BREACHED',
      'UNASSIGNED_HIGH_PRIORITY',
      'LOW_CSAT_PATTERN'
    )),
  CONSTRAINT stays_support_operational_signals_severity_check
    CHECK (severity IN ('INFO', 'LOW', 'MEDIUM', 'HIGH', 'URGENT')),
  CONSTRAINT stays_support_operational_signals_status_check
    CHECK (status IN ('ACTIVE', 'ACKNOWLEDGED', 'RESOLVED')),
  CONSTRAINT stays_support_operational_signals_dedupe_key_unique
    UNIQUE (dedupe_key)
);

CREATE INDEX IF NOT EXISTS idx_stays_support_ops_signals_queue
  ON stays_support_operational_signals (status, severity, last_detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_stays_support_ops_signals_ticket
  ON stays_support_operational_signals (ticket_id)
  WHERE ticket_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stays_support_ops_signals_report
  ON stays_support_operational_signals (report_id)
  WHERE report_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stays_support_ops_signals_safety
  ON stays_support_operational_signals (safety_issue_id)
  WHERE safety_issue_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stays_support_ops_signals_type_status
  ON stays_support_operational_signals (signal_type, status);

COMMIT;
