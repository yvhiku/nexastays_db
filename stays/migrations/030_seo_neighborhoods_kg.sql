-- SEO Release 3: neighborhoods, landmarks, destination knowledge graph

CREATE TABLE IF NOT EXISTS seo_neighborhoods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  destination_id UUID NOT NULL REFERENCES seo_destinations(id) ON DELETE CASCADE,
  slug VARCHAR(64) NOT NULL,
  name VARCHAR(120) NOT NULL,
  search_term VARCHAR(120) NOT NULL,
  latitude DECIMAL(10, 7),
  longitude DECIMAL(11, 8),
  priority INT NOT NULL DEFAULT 50,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (destination_id, slug)
);

CREATE TABLE IF NOT EXISTS seo_landmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug VARCHAR(80) NOT NULL UNIQUE,
  url_slug VARCHAR(96) NOT NULL UNIQUE,
  name VARCHAR(160) NOT NULL,
  destination_id UUID REFERENCES seo_destinations(id) ON DELETE SET NULL,
  search_city VARCHAR(120) NOT NULL,
  latitude DECIMAL(10, 7) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  radius_km DECIMAL(5, 2) NOT NULL DEFAULT 2.0,
  priority INT NOT NULL DEFAULT 50,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS seo_destination_relations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_destination_id UUID NOT NULL REFERENCES seo_destinations(id) ON DELETE CASCADE,
  to_destination_id UUID NOT NULL REFERENCES seo_destinations(id) ON DELETE CASCADE,
  relation_type VARCHAR(32) NOT NULL
    CHECK (relation_type IN ('near', 'similar', 'beach_alternative', 'luxury_alternative', 'day_trip', 'surf_alternative')),
  weight INT NOT NULL DEFAULT 50,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (from_destination_id, to_destination_id, relation_type)
);

CREATE INDEX IF NOT EXISTS idx_seo_neighborhoods_dest ON seo_neighborhoods (destination_id);
CREATE INDEX IF NOT EXISTS idx_seo_landmarks_dest ON seo_landmarks (destination_id);
CREATE INDEX IF NOT EXISTS idx_seo_relations_from ON seo_destination_relations (from_destination_id, relation_type);

-- Neighborhoods (from explore city catalog)
INSERT INTO seo_neighborhoods (destination_id, slug, name, search_term, latitude, longitude, priority)
SELECT d.id, n.slug, n.name, n.search_term, n.lat, n.lng, n.priority
FROM seo_destinations d
JOIN (VALUES
  ('marrakech', 'medina', 'Medina', 'Medina', 31.6329766, -7.9884912, 95),
  ('marrakech', 'gueliz', 'Gueliz', 'Gueliz', 31.6321881, -8.0108135, 90),
  ('marrakech', 'hivernage', 'Hivernage', 'Hivernage', 31.6225589, -8.0083128, 88),
  ('marrakech', 'palmeraie', 'Palmeraie', 'Palmeraie', 31.6747627, -7.982627, 75),
  ('casablanca', 'maarif', 'Maarif', 'Maarif', 33.5708072, -7.6282984, 92),
  ('casablanca', 'ain-diab', 'Ain Diab', 'Ain Diab', 33.5811626, -7.6843877, 90),
  ('casablanca', 'habous', 'Habous', 'Habous', 33.5745744, -7.5970263, 85),
  ('casablanca', 'anfa', 'Anfa', 'Anfa', 33.5785572, -7.690557, 82),
  ('casablanca', 'sidi-maarouf', 'Sidi Maarouf', 'Sidi Maarouf', 33.5286123, -7.646462, 78),
  ('casablanca', 'gauthier', 'Gauthier', 'Gauthier', 33.5898333, -7.6306305, 80),
  ('agadir', 'marina', 'Marina', 'Marina', 30.4250461, -9.6170696, 92),
  ('agadir', 'founty', 'Founty', 'Founty', 30.3945833, -9.5931204, 88),
  ('agadir', 'talborjt', 'Talborjt', 'Talborjt', 30.4237254, -9.5905693, 85),
  ('agadir', 'sonaba', 'Sonaba', 'Sonaba', 30.3996557, -9.5878933, 75),
  ('rabat', 'agdal', 'Agdal', 'Agdal', 33.9983119, -6.8542908, 90),
  ('rabat', 'souissi', 'Souissi', 'Souissi', 33.9688418, -6.8348164, 85),
  ('rabat', 'hassan', 'Hassan', 'Hassan', 34.0202422, -6.8235174, 88),
  ('rabat', 'medina', 'Medina', 'Medina', 34.0255, -6.8345, 86),
  ('fes', 'fes-el-bali', 'Fes el-Bali', 'Fes el-Bali', 34.0631192, -4.9737999, 95),
  ('fes', 'ville-nouvelle', 'Ville Nouvelle', 'Ville Nouvelle', 34.0295238, -4.9948257, 82),
  ('fes', 'mellah', 'Mellah', 'Mellah', 34.0585, -4.9785, 78),
  ('tangier', 'kasbah', 'Kasbah', 'Kasbah', 35.7887531, -5.8134345, 92),
  ('tangier', 'malabata', 'Malabata', 'Malabata', 35.7785399, -5.7768691, 88),
  ('tangier', 'marshan', 'Marshan', 'Marshan', 35.7900018, -5.8207537, 80),
  ('tangier', 'iberia', 'Iberia', 'Iberia', 35.7825706, -5.8208983, 75),
  ('essaouira', 'medina', 'Medina', 'Medina', 31.5145596, -9.7688948, 95),
  ('essaouira', 'diabat', 'Diabat', 'Diabat', 31.4792348, -9.7655371, 80),
  ('chefchaouen', 'medina', 'Medina', 'Medina', 35.1693741, -5.2612741, 95),
  ('chefchaouen', 'ras-el-ma', 'Ras El Ma', 'Ras El Ma', 35.1714905, -5.2560915, 85),
  ('tetouan', 'medina', 'Medina', 'Medina', 35.5710625, -5.3664659, 92),
  ('tetouan', 'ensanche', 'Ensanche', 'Ensanche', 35.5762, -5.3688, 80),
  ('ifrane', 'centre-ville', 'Centre-ville', 'Centre-ville', 33.527605, -5.107408, 90)
) AS n(city_slug, slug, name, search_term, lat, lng, priority) ON d.slug = n.city_slug
ON CONFLICT (destination_id, slug) DO NOTHING;

-- Landmarks (near-* URL slugs)
INSERT INTO seo_landmarks (slug, url_slug, name, destination_id, search_city, latitude, longitude, radius_km, priority)
SELECT lm.slug, lm.url_slug, lm.name, d.id, lm.search_city, lm.lat, lm.lng, lm.radius_km, lm.priority
FROM (VALUES
  ('jemaa-el-fnaa', 'near-jemaa-el-fnaa', 'Jemaa el-Fnaa', 'marrakech', 'Marrakech', 31.6258257, -7.9891608, 1.5, 98),
  ('koutoubia', 'near-koutoubia', 'Koutoubia Mosque', 'marrakech', 'Marrakech', 31.6238889, -7.9938889, 1.0, 95),
  ('bahia-palace', 'near-bahia-palace', 'Bahia Palace', 'marrakech', 'Marrakech', 31.6217, -7.9847, 1.0, 90),
  ('hassan-ii-mosque', 'near-hassan-ii-mosque', 'Hassan II Mosque', 'casablanca', 'Casablanca', 33.6086, -7.6328, 2.0, 98),
  ('mohammed-v-square', 'near-mohammed-v-square', 'Mohammed V Square', 'casablanca', 'Casablanca', 33.5933, -7.6167, 1.5, 88),
  ('hassan-tower', 'near-hassan-tower', 'Hassan Tower', 'rabat', 'Rabat', 34.0244, -6.8225, 1.5, 95),
  ('kasbah-oudayas', 'near-kasbah-oudayas', 'Kasbah of the Udayas', 'rabat', 'Rabat', 34.0311, -6.8367, 1.5, 92),
  ('chouara-tannery', 'near-chouara-tannery', 'Chouara Tannery', 'fes', 'Fes', 34.0661, -4.9717, 1.0, 95),
  ('bab-bou-jeloud', 'near-bab-bou-jeloud', 'Bab Bou Jeloud', 'fes', 'Fes', 34.0525, -4.9986, 1.0, 90),
  ('tangier-medina', 'near-tangier-medina', 'Tangier Medina', 'tangier', 'Tangier', 35.7887531, -5.8134345, 1.5, 90),
  ('essaouira-ramparts', 'near-essaouira-ramparts', 'Essaouira Ramparts', 'essaouira', 'Essaouira', 31.5145596, -9.7688948, 1.5, 92),
  ('chefchaouen-medina', 'near-chefchaouen-medina', 'Chefchaouen Medina', 'chefchaouen', 'Chefchaouen', 35.1693741, -5.2612741, 1.5, 95),
  ('agadir-beach', 'near-agadir-beach', 'Agadir Beach', 'agadir', 'Agadir', 30.4278, -9.5981, 2.5, 90)
) AS lm(slug, url_slug, name, city_slug, search_city, lat, lng, radius_km, priority)
LEFT JOIN seo_destinations d ON d.slug = lm.city_slug
ON CONFLICT (slug) DO NOTHING;

-- Knowledge graph (typed destination relations)
INSERT INTO seo_destination_relations (from_destination_id, to_destination_id, relation_type, weight)
SELECT f.id, t.id, r.relation_type, r.weight
FROM (VALUES
  ('marrakech', 'essaouira', 'beach_alternative', 90),
  ('marrakech', 'agadir', 'beach_alternative', 85),
  ('marrakech', 'fes', 'similar', 80),
  ('casablanca', 'rabat', 'near', 88),
  ('casablanca', 'marrakech', 'similar', 75),
  ('casablanca', 'tangier', 'near', 82),
  ('agadir', 'essaouira', 'surf_alternative', 78),
  ('agadir', 'marrakech', 'similar', 70),
  ('rabat', 'casablanca', 'near', 88),
  ('rabat', 'fes', 'similar', 72),
  ('fes', 'chefchaouen', 'day_trip', 80),
  ('tangier', 'chefchaouen', 'day_trip', 88),
  ('tangier', 'tetouan', 'near', 82),
  ('essaouira', 'marrakech', 'similar', 75),
  ('chefchaouen', 'fes', 'similar', 70)
) AS r(from_slug, to_slug, relation_type, weight)
JOIN seo_destinations f ON f.slug = r.from_slug
JOIN seo_destinations t ON t.slug = r.to_slug
ON CONFLICT (from_destination_id, to_destination_id, relation_type) DO NOTHING;

-- City × neighborhood registry pages
INSERT INTO seo_page_registry (page_type, slug, locale, path, status, priority, indexable, destination_id, lastmod)
SELECT 'city_neighborhood', d.slug || '/' || n.slug, loc.locale,
       '/' || loc.locale || '/stays/' || d.slug || '/' || n.slug,
       'published', 0.80, false, d.id, NOW()
FROM seo_neighborhoods n
JOIN seo_destinations d ON d.id = n.destination_id
CROSS JOIN (VALUES ('en'), ('fr'), ('ar')) AS loc(locale)
WHERE n.active = true AND d.content_status = 'published'
ON CONFLICT (page_type, slug, locale) DO NOTHING;

-- Landmark registry pages
INSERT INTO seo_page_registry (page_type, slug, locale, path, status, priority, indexable, destination_id, lastmod)
SELECT 'landmark', lm.url_slug, loc.locale,
       '/' || loc.locale || '/stays/' || lm.url_slug,
       'published', 0.78, false, lm.destination_id, NOW()
FROM seo_landmarks lm
CROSS JOIN (VALUES ('en'), ('fr'), ('ar')) AS loc(locale)
WHERE lm.active = true
ON CONFLICT (page_type, slug, locale) DO NOTHING;
