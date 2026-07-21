-- SEO Release 2: property types, amenities, combo page registry

CREATE TABLE IF NOT EXISTS seo_property_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug VARCHAR(64) NOT NULL UNIQUE,
  listing_type VARCHAR(20) NOT NULL,
  label VARCHAR(80) NOT NULL,
  plural_label VARCHAR(80) NOT NULL,
  priority INT NOT NULL DEFAULT 50,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS seo_amenities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug VARCHAR(64) NOT NULL UNIQUE,
  filter_kind VARCHAR(32) NOT NULL,
  amenity_tag VARCHAR(64),
  label VARCHAR(80) NOT NULL,
  priority INT NOT NULL DEFAULT 50,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO seo_property_types (slug, listing_type, label, plural_label, priority) VALUES
  ('apartments', 'APARTMENT', 'Apartment', 'Apartments', 90),
  ('hotels', 'HOTEL', 'Hotel', 'Hotels', 85),
  ('riads', 'RIAD', 'Riad', 'Riads', 95),
  ('villas', 'VILLA', 'Villa', 'Villas', 88),
  ('hostels', 'HOSTEL', 'Hostel', 'Hostels', 70)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO seo_amenities (slug, filter_kind, amenity_tag, label, priority) VALUES
  ('pool', 'amenity', 'pool', 'Pool', 95),
  ('pet-friendly', 'pets', NULL, 'Pet-friendly', 90),
  ('free-parking', 'amenity', 'parking', 'Free parking', 85),
  ('wifi', 'amenity', 'wifi', 'WiFi', 80),
  ('family', 'family', NULL, 'Family-friendly', 75),
  ('luxury', 'luxury', NULL, 'Luxury', 92)
ON CONFLICT (slug) DO NOTHING;

-- Global property type pages (en/fr/ar)
INSERT INTO seo_page_registry (page_type, slug, locale, path, status, priority, indexable, lastmod)
SELECT 'property_type', pt.slug, loc.locale,
       '/' || loc.locale || '/stays/' || pt.slug,
       'published', 0.75, false, NOW()
FROM seo_property_types pt
CROSS JOIN (VALUES ('en'), ('fr'), ('ar')) AS loc(locale)
ON CONFLICT (page_type, slug, locale) DO NOTHING;

-- Global amenity pages (en/fr/ar)
INSERT INTO seo_page_registry (page_type, slug, locale, path, status, priority, indexable, lastmod)
SELECT 'amenity', a.slug, loc.locale,
       '/' || loc.locale || '/stays/' || a.slug,
       'published', 0.75, false, NOW()
FROM seo_amenities a
CROSS JOIN (VALUES ('en'), ('fr'), ('ar')) AS loc(locale)
ON CONFLICT (page_type, slug, locale) DO NOTHING;

-- City × property type combo pages
INSERT INTO seo_page_registry (page_type, slug, locale, path, status, priority, indexable, destination_id, lastmod)
SELECT 'city_property_type', d.slug || '/' || pt.slug, loc.locale,
       '/' || loc.locale || '/stays/' || d.slug || '/' || pt.slug,
       'published', 0.85, false, d.id, NOW()
FROM seo_destinations d
CROSS JOIN seo_property_types pt
CROSS JOIN (VALUES ('en'), ('fr'), ('ar')) AS loc(locale)
WHERE d.content_status = 'published'
ON CONFLICT (page_type, slug, locale) DO NOTHING;

-- City × amenity combo pages
INSERT INTO seo_page_registry (page_type, slug, locale, path, status, priority, indexable, destination_id, lastmod)
SELECT 'city_amenity', d.slug || '/' || a.slug, loc.locale,
       '/' || loc.locale || '/stays/' || d.slug || '/' || a.slug,
       'published', 0.85, false, d.id, NOW()
FROM seo_destinations d
CROSS JOIN seo_amenities a
CROSS JOIN (VALUES ('en'), ('fr'), ('ar')) AS loc(locale)
WHERE d.content_status = 'published'
ON CONFLICT (page_type, slug, locale) DO NOTHING;
