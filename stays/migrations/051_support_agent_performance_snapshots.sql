-- Loop 4: daily UTC-day agent performance facts (not a rolling 30-day rollup)

BEGIN;

CREATE TABLE IF NOT EXISTS stays_support_agent_performance_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_user_id VARCHAR(128) NOT NULL,
  snapshot_date DATE NOT NULL,

  tickets_closed INT NOT NULL DEFAULT 0,
  tickets_reopened INT NOT NULL DEFAULT 0,

  review_count INT NOT NULL DEFAULT 0,
  average_agent_rating NUMERIC(4, 2) NULL,
  problem_solved_count INT NOT NULL DEFAULT 0,
  problem_not_solved_count INT NOT NULL DEFAULT 0,
  problem_solved_rate NUMERIC(6, 4) NULL,
  overall_average_rating NUMERIC(4, 2) NULL,

  first_response_count INT NOT NULL DEFAULT 0,
  first_response_sla_met INT NOT NULL DEFAULT 0,
  first_response_sla_rate NUMERIC(6, 4) NULL,
  resolution_count INT NOT NULL DEFAULT 0,
  resolution_sla_met INT NOT NULL DEFAULT 0,
  resolution_sla_rate NUMERIC(6, 4) NULL,

  average_first_response_seconds INT NULL,
  average_resolution_seconds INT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT stays_support_agent_perf_snap_unique
    UNIQUE (agent_user_id, snapshot_date)
);

CREATE INDEX IF NOT EXISTS idx_stays_support_agent_perf_snap_date
  ON stays_support_agent_performance_snapshots (snapshot_date);

COMMIT;
