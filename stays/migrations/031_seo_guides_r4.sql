-- SEO Release 4: Knowledge Hub guides, CMS locale support, GEO monitoring

ALTER TABLE seo_guides
  ADD COLUMN IF NOT EXISTS locale CHAR(2) NOT NULL DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS seo_score INT NOT NULL DEFAULT 0;

ALTER TABLE seo_guides DROP CONSTRAINT IF EXISTS seo_guides_slug_key;
CREATE UNIQUE INDEX IF NOT EXISTS idx_seo_guides_slug_locale ON seo_guides (slug, locale);

CREATE TABLE IF NOT EXISTS seo_geo_request_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint VARCHAR(64) NOT NULL,
  page_slug VARCHAR(160),
  locale CHAR(2),
  user_agent TEXT,
  referrer TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_seo_geo_log_requested ON seo_geo_request_log (requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_seo_geo_log_slug ON seo_geo_request_log (page_slug, requested_at DESC);

-- Seed Tier-A travel guides (en) with published content
INSERT INTO seo_guides (slug, locale, guide_type, destination_id, seo_title, seo_description, body_html, geo_blocks_json, content_status, indexable, seo_score, published_at)
SELECT
  d.slug || '-travel-guide', 'en', 'travel', d.id,
  'Travel Guide to ' || d.name || ' | Nexa Stays',
  'Plan your trip to ' || d.name || ' with verified stays, local tips, and live marketplace pricing on Nexa Stays.',
  '<p>' || d.name || ' is one of Morocco''s most searched destinations on Nexa Stays. Use this guide to compare neighborhoods, understand average nightly prices, and book verified listings with transparent fees.</p><p>Best time to visit: ' || COALESCE(d.best_time_to_visit, 'year-round') || '.</p>',
  jsonb_build_array(
    jsonb_build_object('question', 'How many verified stays are in ' || d.name || '?', 'answer', 'Check live listing counts on Nexa Stays — updated daily from the marketplace.'),
    jsonb_build_object('question', 'Is ' || d.name || ' safe for tourists?', 'answer', 'Popular tourist districts are generally safe when booking verified stays through Nexa Stays.')
  ),
  'published', true, 82, NOW()
FROM seo_destinations d WHERE d.content_status = 'published'
ON CONFLICT (slug, locale) DO NOTHING;

-- Seasonal guides (en)
INSERT INTO seo_guides (slug, locale, guide_type, destination_id, seo_title, seo_description, body_html, geo_blocks_json, content_status, indexable, seo_score, published_at)
SELECT
  d.slug || '-best-time-to-visit', 'en', 'seasonal', d.id,
  'Best Time to Visit ' || d.name || ' | Nexa Stays',
  'When to visit ' || d.name || ' — weather, crowds, and pricing insights from Nexa Stays marketplace data.',
  '<p>The best time to visit ' || d.name || ' is ' || COALESCE(d.best_time_to_visit, 'during spring and autumn for comfortable weather') || '. Shoulder seasons often offer better availability on Nexa Stays.</p>',
  '[]'::jsonb,
  'published', true, 80, NOW()
FROM seo_destinations d WHERE d.content_status = 'published'
ON CONFLICT (slug, locale) DO NOTHING;

-- Experience guides (en)
INSERT INTO seo_guides (slug, locale, guide_type, destination_id, seo_title, seo_description, body_html, geo_blocks_json, content_status, indexable, seo_score, published_at)
SELECT
  d.slug || '-things-to-do', 'en', 'experience', d.id,
  'Things to Do in ' || d.name || ' | Nexa Stays',
  'Top experiences and neighborhoods in ' || d.name || ' — plan your stay with Nexa Stays verified listings.',
  '<p>Explore ' || d.name || ' by neighborhood. Browse stays in the medina, modern districts, and nearby day-trip areas on Nexa Stays.</p>',
  '[]'::jsonb,
  'published', true, 78, NOW()
FROM seo_destinations d WHERE d.content_status = 'published'
ON CONFLICT (slug, locale) DO NOTHING;

-- Morocco-wide guides (en)
INSERT INTO seo_guides (slug, locale, guide_type, destination_id, seo_title, seo_description, body_html, content_status, indexable, seo_score, published_at)
VALUES
  ('morocco-travel-guide', 'en', 'travel', NULL,
   'Morocco Travel Guide | Nexa Stays',
   'Complete Morocco travel guide — cities, riads, beaches, and verified stays on Nexa Stays.',
   '<p>Morocco offers imperial cities, Atlantic beaches, mountain escapes, and desert experiences. Nexa Stays connects you with verified hosts across Marrakech, Casablanca, Fes, Agadir, and more.</p>',
   'published', true, 85, NOW()),
  ('visiting-morocco-in-ramadan', 'en', 'event', NULL,
   'Visiting Morocco During Ramadan | Nexa Stays',
   'What to expect when traveling in Morocco during Ramadan — etiquette, dining, and stays on Nexa Stays.',
   '<p>During Ramadan, many restaurants adjust hours and the medina atmosphere changes in the evening. Book verified stays on Nexa Stays and confirm check-in times with your host.</p>',
   'published', true, 76, NOW())
ON CONFLICT (slug, locale) DO NOTHING;

-- French + Arabic copies (published, same slugs)
INSERT INTO seo_guides (slug, locale, guide_type, destination_id, seo_title, seo_description, body_html, geo_blocks_json, content_status, indexable, seo_score, published_at)
SELECT slug, 'fr', guide_type, destination_id,
  REPLACE(seo_title, ' | Nexa Stays', ' | Nexa Stays'),
  seo_description, body_html, geo_blocks_json, content_status, indexable, seo_score, published_at
FROM seo_guides WHERE locale = 'en'
ON CONFLICT (slug, locale) DO NOTHING;

INSERT INTO seo_guides (slug, locale, guide_type, destination_id, seo_title, seo_description, body_html, geo_blocks_json, content_status, indexable, seo_score, published_at)
SELECT slug, 'ar', guide_type, destination_id,
  seo_title, seo_description, body_html, geo_blocks_json, content_status, indexable, seo_score, published_at
FROM seo_guides WHERE locale = 'en'
ON CONFLICT (slug, locale) DO NOTHING;

-- Guide page registry (all published guides × locales)
INSERT INTO seo_page_registry (page_type, slug, locale, path, status, priority, indexable, seo_score, destination_id, lastmod)
SELECT 'guide', g.slug, g.locale,
       '/' || g.locale || '/guides/' || g.slug,
       'published', 0.72, g.indexable, g.seo_score, g.destination_id, NOW()
FROM seo_guides g WHERE g.content_status = 'published'
ON CONFLICT (page_type, slug, locale) DO NOTHING;

-- Initial content versions (published v1)
INSERT INTO seo_content_versions (entity_type, entity_id, locale, version, field_name, content_html, status, published_at)
SELECT 'guide', g.id, g.locale, 1, 'body_html', g.body_html, 'published', g.published_at
FROM seo_guides g WHERE g.content_status = 'published'
ON CONFLICT (entity_type, entity_id, locale, field_name, version) DO NOTHING;
