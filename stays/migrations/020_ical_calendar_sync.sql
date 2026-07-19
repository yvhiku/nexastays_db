-- Phase 1 iCal calendar sync
-- External calendars, UID events, ICAL blocks, export tokens, sync logs

ALTER TABLE stays_availability_blocks
  DROP CONSTRAINT IF EXISTS stays_availability_blocks_source_check;

ALTER TABLE stays_availability_blocks
  ADD CONSTRAINT stays_availability_blocks_source_check
  CHECK (source IS NULL OR source IN ('HOST', 'ADMIN', 'BOOKING', 'ICAL'));

ALTER TABLE stays_availability_blocks
  ADD COLUMN IF NOT EXISTS external_calendar_id UUID NULL;

ALTER TABLE stays_listings
  ADD COLUMN IF NOT EXISTS calendar_export_token UUID NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_stays_listings_calendar_export_token
  ON stays_listings (calendar_export_token)
  WHERE calendar_export_token IS NOT NULL;

CREATE TABLE IF NOT EXISTS stays_external_calendars (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES stays_listings(id) ON DELETE CASCADE,
  provider VARCHAR(20) NOT NULL
    CHECK (provider IN ('AIRBNB', 'BOOKING', 'VRBO', 'GOOGLE', 'APPLE', 'DIRECT', 'OTHER')),
  provider_listing_reference VARCHAR(120) NULL,
  label VARCHAR(120) NOT NULL DEFAULT '',
  ics_url TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'SYNCING', 'ERROR', 'PAUSED')),
  next_sync_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_until TIMESTAMPTZ NULL,
  last_attempt_at TIMESTAMPTZ NULL,
  last_successful_sync_at TIMESTAMPTZ NULL,
  last_error TEXT NULL,
  etag TEXT NULL,
  last_modified TEXT NULL,
  sync_version INT NOT NULL DEFAULT 1,
  consecutive_failures INT NOT NULL DEFAULT 0,
  sync_result JSONB NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stays_external_calendars_next_sync
  ON stays_external_calendars (next_sync_at)
  WHERE status IN ('ACTIVE', 'ERROR');

CREATE INDEX IF NOT EXISTS idx_stays_external_calendars_listing
  ON stays_external_calendars (listing_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_stays_external_calendars_listing_url
  ON stays_external_calendars (listing_id, ics_url);

ALTER TABLE stays_availability_blocks
  ADD CONSTRAINT fk_stays_availability_blocks_external_calendar
  FOREIGN KEY (external_calendar_id)
  REFERENCES stays_external_calendars(id)
  ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_stays_availability_blocks_external_calendar
  ON stays_availability_blocks (external_calendar_id)
  WHERE external_calendar_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS stays_external_calendar_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_calendar_id UUID NOT NULL REFERENCES stays_external_calendars(id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  recurrence_id TEXT NOT NULL DEFAULT '',
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  summary TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (external_calendar_id, uid, recurrence_id)
);

CREATE INDEX IF NOT EXISTS idx_stays_external_calendar_events_cal
  ON stays_external_calendar_events (external_calendar_id);

CREATE TABLE IF NOT EXISTS stays_external_calendar_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_calendar_id UUID NOT NULL REFERENCES stays_external_calendars(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ NULL,
  outcome VARCHAR(30) NOT NULL
    CHECK (outcome IN ('SUCCESS', 'NOT_MODIFIED', 'TIMEOUT', 'ERROR')),
  message TEXT NULL,
  imported_events INT NULL,
  removed_events INT NULL,
  blocked_nights INT NULL,
  duration_ms INT NULL
);

CREATE INDEX IF NOT EXISTS idx_stays_external_calendar_sync_logs_cal_started
  ON stays_external_calendar_sync_logs (external_calendar_id, started_at DESC);
