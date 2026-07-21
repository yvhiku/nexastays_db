-- SEO platform: destinations, page registry, content versions, guides (Release 1)

CREATE TABLE IF NOT EXISTS seo_destinations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug VARCHAR(120) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  country_code CHAR(2) NOT NULL DEFAULT 'MA',
  region_id VARCHAR(64),
  latitude DECIMAL(10, 7),
  longitude DECIMAL(11, 8),
  bounds_json JSONB,
  hero_image_url TEXT,
  best_time_to_visit TEXT,
  nearby_city_slugs TEXT[] NOT NULL DEFAULT '{}',
  geo_blocks_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  stats_cache_json JSONB,
  stats_refreshed_at TIMESTAMPTZ,
  listing_count_cache INT NOT NULL DEFAULT 0,
  seo_score INT NOT NULL DEFAULT 0,
  content_status VARCHAR(20) NOT NULL DEFAULT 'published'
    CHECK (content_status IN ('draft', 'review', 'published', 'archived')),
  indexable BOOLEAN NOT NULL DEFAULT false,
  search_city VARCHAR(120) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_seo_destinations_slug ON seo_destinations (slug);
CREATE INDEX IF NOT EXISTS idx_seo_destinations_indexable ON seo_destinations (indexable) WHERE indexable = true;
CREATE INDEX IF NOT EXISTS idx_seo_destinations_search_city ON seo_destinations (LOWER(search_city));

CREATE TABLE IF NOT EXISTS seo_page_registry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  page_type VARCHAR(32) NOT NULL,
  slug VARCHAR(160) NOT NULL,
  locale CHAR(2) NOT NULL,
  path VARCHAR(512) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'published'
    CHECK (status IN ('draft', 'review', 'published', 'archived')),
  priority DECIMAL(2, 1) NOT NULL DEFAULT 0.8,
  indexable BOOLEAN NOT NULL DEFAULT false,
  seo_score INT NOT NULL DEFAULT 0,
  destination_id UUID REFERENCES seo_destinations(id) ON DELETE CASCADE,
  guide_id UUID,
  lastmod TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (page_type, slug, locale)
);

CREATE INDEX IF NOT EXISTS idx_seo_page_registry_indexable ON seo_page_registry (indexable, locale) WHERE indexable = true;
CREATE INDEX IF NOT EXISTS idx_seo_page_registry_type_slug ON seo_page_registry (page_type, slug);

CREATE TABLE IF NOT EXISTS seo_content_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type VARCHAR(32) NOT NULL,
  entity_id UUID NOT NULL,
  locale CHAR(2) NOT NULL,
  version INT NOT NULL DEFAULT 1,
  field_name VARCHAR(64) NOT NULL,
  content_html TEXT,
  content_json JSONB,
  status VARCHAR(20) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'review', 'published', 'archived')),
  created_by UUID,
  approved_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  published_at TIMESTAMPTZ,
  UNIQUE (entity_type, entity_id, locale, field_name, version)
);

CREATE INDEX IF NOT EXISTS idx_seo_content_versions_entity ON seo_content_versions (entity_type, entity_id, locale, status);

CREATE TABLE IF NOT EXISTS seo_guides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug VARCHAR(160) NOT NULL UNIQUE,
  guide_type VARCHAR(32) NOT NULL DEFAULT 'travel',
  destination_id UUID REFERENCES seo_destinations(id) ON DELETE SET NULL,
  seo_title VARCHAR(200),
  seo_description TEXT,
  body_html TEXT,
  geo_blocks_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  indexable BOOLEAN NOT NULL DEFAULT false,
  content_status VARCHAR(20) NOT NULL DEFAULT 'draft'
    CHECK (content_status IN ('draft', 'review', 'published', 'archived')),
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tier-A Morocco cities (Release 1 seed)
INSERT INTO seo_destinations (
  slug, name, country_code, region_id, latitude, longitude, bounds_json, hero_image_url,
  best_time_to_visit, nearby_city_slugs, search_city, content_status, indexable, seo_score
) VALUES
  ('marrakech', 'Marrakech', 'MA', 'marrakech_safi', 31.6258257, -7.9891608,
   '{"southwest":{"lat":31.5441986,"lng":-8.0893315},"northeast":{"lat":31.7104265,"lng":-7.8847385}}'::jsonb,
   '/images/assets/marrakesh.jpg', 'March–May and September–November',
   ARRAY['essaouira','agadir','fes'], 'Marrakech', 'published', false, 50),
  ('casablanca', 'Casablanca', 'MA', 'casablanca_settat', 33.5731, -7.5898,
   '{"southwest":{"lat":33.45,"lng":-7.72},"northeast":{"lat":33.65,"lng":-7.48}}'::jsonb,
   '/images/assets/Casablanca-Finance-City-CFC.jpg', 'Year-round; spring and autumn are ideal',
   ARRAY['rabat','marrakech','tangier'], 'Casablanca', 'published', false, 50),
  ('agadir', 'Agadir', 'MA', 'souss_massa', 30.4278, -9.5981,
   '{"southwest":{"lat":30.35,"lng":-9.72},"northeast":{"lat":30.52,"lng":-9.48}}'::jsonb,
   '/images/assets/agadir.jpg', 'April–October for beach weather',
   ARRAY['taghazout','marrakech','essaouira'], 'Agadir', 'published', false, 50),
  ('rabat', 'Rabat', 'MA', 'rabat_sale_kenitra', 34.0209, -6.8416,
   NULL, NULL, 'March–June and September–November',
   ARRAY['casablanca','fes','meknes'], 'Rabat', 'published', false, 50),
  ('fes', 'Fes', 'MA', 'fes_meknes', 34.0181, -5.0078,
   NULL, '/images/assets/fes.jpg', 'March–May and October–November',
   ARRAY['meknes','rabat','chefchaouen'], 'Fes', 'published', false, 50),
  ('tangier', 'Tangier', 'MA', 'tanger_tetouan_al_hoceima', 35.7595, -5.8340,
   NULL, '/images/assets/tangier.jpg', 'April–October',
   ARRAY['tetouan','chefchaouen','casablanca'], 'Tangier', 'published', false, 50),
  ('essaouira', 'Essaouira', 'MA', 'marrakech_safi', 31.5085, -9.7595,
   NULL, NULL, 'April–October',
   ARRAY['marrakech','agadir'], 'Essaouira', 'published', false, 50),
  ('chefchaouen', 'Chefchaouen', 'MA', 'tanger_tetouan_al_hoceima', 35.1688, -5.2636,
   NULL, NULL, 'April–June and September–October',
   ARRAY['tangier','fes','tetouan'], 'Chefchaouen', 'published', false, 50),
  ('tetouan', 'Tetouan', 'MA', 'tanger_tetouan_al_hoceima', 35.5889, -5.3626,
   NULL, NULL, 'Spring and autumn',
   ARRAY['tangier','chefchaouen'], 'Tetouan', 'published', false, 50),
  ('ifrane', 'Ifrane', 'MA', 'fes_meknes', 33.5228, -5.1106,
   NULL, NULL, 'December–March for snow; summer for cool escapes',
   ARRAY['fes','meknes'], 'Ifrane', 'published', false, 50)
ON CONFLICT (slug) DO NOTHING;

-- Register city pages (en/fr/ar) — indexable updated by freshness job from listing counts
INSERT INTO seo_page_registry (page_type, slug, locale, path, status, priority, indexable, destination_id, lastmod)
SELECT 'city', d.slug, loc.locale,
       '/' || loc.locale || '/stays/' || d.slug,
       'published', 0.9, false, d.id, NOW()
FROM seo_destinations d
CROSS JOIN (VALUES ('en'), ('fr'), ('ar')) AS loc(locale)
ON CONFLICT (page_type, slug, locale) DO NOTHING;
