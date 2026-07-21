-- SEO Release 5: universal landing content blocks (neighborhood pilot)

CREATE TABLE IF NOT EXISTS seo_landing_content (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type VARCHAR(32) NOT NULL,
  entity_id UUID NOT NULL,
  locale VARCHAR(5) NOT NULL,
  content_blocks_json JSONB NOT NULL DEFAULT '{}',
  content_status VARCHAR(20) NOT NULL DEFAULT 'published',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (entity_type, entity_id, locale)
);

CREATE INDEX IF NOT EXISTS idx_seo_landing_content_entity
  ON seo_landing_content (entity_type, entity_id, locale);

CREATE INDEX IF NOT EXISTS idx_seo_landing_content_status
  ON seo_landing_content (content_status) WHERE content_status = 'published';
