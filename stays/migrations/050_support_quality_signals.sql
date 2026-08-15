-- Loop 4: quality pattern signal types

BEGIN;

ALTER TABLE stays_support_operational_signals
  DROP CONSTRAINT IF EXISTS stays_support_operational_signals_type_check;

ALTER TABLE stays_support_operational_signals
  ADD CONSTRAINT stays_support_operational_signals_type_check
  CHECK (signal_type IN (
    'REPEAT_REPORT',
    'REPEAT_SAFETY_REPORT',
    'MULTIPLE_OPEN_TICKETS',
    'SLA_ATTENTION',
    'SLA_BREACHED',
    'UNASSIGNED_HIGH_PRIORITY',
    'LOW_CSAT_PATTERN',
    'FOLLOW_UP_REQUIRED',
    'AGENT_LOW_CSAT_PATTERN',
    'AGENT_LOW_SOLVED_RATE',
    'AGENT_SLA_DECLINE',
    'CATEGORY_OUTCOME_DECLINE'
  ));

COMMIT;
