-- SEO FR/AR translated guide + neighborhood landing content (Tier-A Morocco destinations)

-- French travel guides per destination
UPDATE seo_guides g
SET
  seo_title = 'Guide de voyage pour ' || d.name || ' | Nexa Stays',
  seo_description = 'Planifiez votre voyage à ' || d.name || ' avec des séjours vérifiés, des conseils locaux et des prix en direct sur Nexa Stays.',
  body_html = '<p>' || d.name || ' est l''une des destinations les plus recherchées sur Nexa Stays. Utilisez ce guide pour comparer les quartiers, comprendre les prix moyens par nuit et réserver des annonces vérifiées avec des frais transparents.</p><p>Meilleure période : ' || COALESCE(d.best_time_to_visit, 'toute l''année') || '.</p>',
  geo_blocks_json = jsonb_build_array(
    jsonb_build_object('question', 'Combien de séjours vérifiés à ' || d.name || ' ?', 'answer', 'Consultez les annonces live sur Nexa Stays — mises à jour quotidiennement depuis la place de marché.'),
    jsonb_build_object('question', d.name || ' est-elle sûre pour les touristes ?', 'answer', 'Les quartiers touristiques populaires sont généralement sûrs lorsque vous réservez des séjours vérifiés via Nexa Stays.')
  ),
  indexable = true,
  seo_score = GREATEST(g.seo_score, 82)
FROM seo_destinations d
WHERE g.destination_id = d.id
  AND g.locale = 'fr'
  AND g.guide_type = 'travel'
  AND d.slug IN ('marrakech', 'casablanca', 'agadir', 'tangier', 'rabat', 'fes', 'essaouira');

-- Arabic travel guides per destination
UPDATE seo_guides g
SET
  seo_title = 'دليل السفر إلى ' || d.name || ' | Nexa Stays',
  seo_description = 'خطط لرحلتك إلى ' || d.name || ' مع إقامات موثقة ونصائح محلية وأسعار مباشرة على Nexa Stays.',
  body_html = '<p>' || d.name || ' من أكثر الوجهات التي يبحث عنها الضيوف على Nexa Stays. استخدم هذا الدليل لمقارنة الأحياء وفهم متوسط السعر لليلة وحجز إعلانات موثقة برسوم واضحة.</p><p>أفضل وقت للزيارة: ' || COALESCE(d.best_time_to_visit, 'طوال العام') || '.</p>',
  geo_blocks_json = jsonb_build_array(
    jsonb_build_object('question', 'كم عدد الإقامات الموثقة في ' || d.name || '؟', 'answer', 'راجع الإعلانات المباشرة على Nexa Stays — تُحدَّث يوميًا من السوق.'),
    jsonb_build_object('question', 'هل ' || d.name || ' آمنة للسياح؟', 'answer', 'الأحياء السياحية الشائعة آمنة عمومًا عند حجز إقامات موثقة عبر Nexa Stays.')
  ),
  indexable = true,
  seo_score = GREATEST(g.seo_score, 82)
FROM seo_destinations d
WHERE g.destination_id = d.id
  AND g.locale = 'ar'
  AND g.guide_type = 'travel'
  AND d.slug IN ('marrakech', 'casablanca', 'agadir', 'tangier', 'rabat', 'fes', 'essaouira');

-- French seasonal + experience guides (destination-scoped)
UPDATE seo_guides g
SET
  seo_title = CASE g.guide_type
    WHEN 'seasonal' THEN 'Meilleure période pour visiter ' || d.name || ' | Nexa Stays'
    WHEN 'experience' THEN 'Activités à ' || d.name || ' | Nexa Stays'
    ELSE g.seo_title
  END,
  seo_description = CASE g.guide_type
    WHEN 'seasonal' THEN 'Quand visiter ' || d.name || ' — météo, affluence et tendances de prix sur Nexa Stays.'
    WHEN 'experience' THEN 'Quartiers et expériences incontournables à ' || d.name || ' — planifiez votre séjour avec Nexa Stays.'
    ELSE g.seo_description
  END,
  indexable = true,
  seo_score = GREATEST(g.seo_score, 78)
FROM seo_destinations d
WHERE g.destination_id = d.id
  AND g.locale = 'fr'
  AND g.guide_type IN ('seasonal', 'experience')
  AND d.slug IN ('marrakech', 'casablanca', 'agadir', 'tangier', 'rabat', 'fes', 'essaouira');

-- Morocco-wide guides FR
UPDATE seo_guides
SET
  seo_title = 'Guide de voyage au Maroc | Nexa Stays',
  seo_description = 'Guide complet du Maroc — villes, riads, plages et séjours vérifiés sur Nexa Stays.',
  body_html = '<p>Le Maroc offre villes impériales, plages atlantiques, montagnes et désert. Nexa Stays vous connecte à des hôtes vérifiés à Marrakech, Casablanca, Fès, Agadir et plus encore.</p>',
  indexable = true,
  seo_score = GREATEST(seo_score, 85)
WHERE slug = 'morocco-travel-guide' AND locale = 'fr';

UPDATE seo_guides
SET
  seo_title = 'Visiter le Maroc pendant le Ramadan | Nexa Stays',
  seo_description = 'À quoi s''attendre en voyage au Maroc pendant le Ramadan — étiquette, restauration et séjours sur Nexa Stays.',
  body_html = '<p>Pendant le Ramadan, les horaires des restaurants évoluent et l''ambiance de la médina change le soir. Réservez des séjours vérifiés sur Nexa Stays et confirmez les heures d''arrivée avec votre hôte.</p>',
  indexable = true,
  seo_score = GREATEST(seo_score, 76)
WHERE slug = 'visiting-morocco-in-ramadan' AND locale = 'fr';

-- Morocco-wide guides AR
UPDATE seo_guides
SET
  seo_title = 'دليل السفر إلى المغرب | Nexa Stays',
  seo_description = 'دليل شامل للمغرب — مدن ورياض وشواطئ وإقامات موثقة على Nexa Stays.',
  body_html = '<p>يقدم المغرب مدنًا إمبراطورية وشواطئ أطلسية وجبال وصحارى. يربطك Nexa Stays بمضيفين موثقين في مراكش والدار البيضاء وفاس وأكادير وغيرها.</p>',
  indexable = true,
  seo_score = GREATEST(seo_score, 85)
WHERE slug = 'morocco-travel-guide' AND locale = 'ar';

UPDATE seo_guides
SET
  seo_title = 'زيارة المغرب في رمضان | Nexa Stays',
  seo_description = 'ما يمكن توقعه عند السفر إلى المغرب في رمضان — آداب وتموين وإقامات على Nexa Stays.',
  body_html = '<p>خلال رمضان تتغير أوقات المطاعم ويتبدل أجواء المدينة القديمة في المساء. احجز إقامات موثقة على Nexa Stays وأكد أوقات الوصول مع المضيف.</p>',
  indexable = true,
  seo_score = GREATEST(seo_score, 76)
WHERE slug = 'visiting-morocco-in-ramadan' AND locale = 'ar';

-- FR neighborhood landing blocks (top neighborhoods per Tier-A city)
INSERT INTO seo_landing_content (entity_type, entity_id, locale, content_blocks_json, content_status)
SELECT
  'neighborhood',
  n.id,
  'fr',
  jsonb_build_object(
    'hero_intro', 'Découvrez ' || n.name || ' — un quartier recherché pour les séjours de courte durée.',
    'why_stay_here', 'Réservez des séjours vérifiés dans ' || n.name || ' avec des règles claires, des hôtes contrôlés et des tarifs transparents sur Nexa Stays.',
    'highlights', jsonb_build_array('Séjours vérifiés', 'Quartier central', 'Tarifs transparents')
  ),
  'published'
FROM seo_neighborhoods n
JOIN seo_destinations d ON d.id = n.destination_id
WHERE d.slug IN ('marrakech', 'casablanca', 'agadir', 'tangier', 'rabat', 'fes', 'essaouira')
  AND n.priority <= 3
ON CONFLICT (entity_type, entity_id, locale) DO UPDATE SET
  content_blocks_json = EXCLUDED.content_blocks_json,
  content_status = 'published',
  updated_at = NOW();

-- AR neighborhood landing blocks
INSERT INTO seo_landing_content (entity_type, entity_id, locale, content_blocks_json, content_status)
SELECT
  'neighborhood',
  n.id,
  'ar',
  jsonb_build_object(
    'hero_intro', 'اكتشف ' || n.name || ' — حي مطلوب للإقامات قصيرة المدة.',
    'why_stay_here', 'احجز إقامات موثقة في ' || n.name || ' بقواعد واضحة ومضيفين موثوقين وأسعار شفافة على Nexa Stays.',
    'highlights', jsonb_build_array('إقامات موثقة', 'حي مركزي', 'أسعار واضحة')
  ),
  'published'
FROM seo_neighborhoods n
JOIN seo_destinations d ON d.id = n.destination_id
WHERE d.slug IN ('marrakech', 'casablanca', 'agadir', 'tangier', 'rabat', 'fes', 'essaouira')
  AND n.priority <= 3
ON CONFLICT (entity_type, entity_id, locale) DO UPDATE SET
  content_blocks_json = EXCLUDED.content_blocks_json,
  content_status = 'published',
  updated_at = NOW();

-- Refresh published content versions for updated guides
INSERT INTO seo_content_versions (entity_type, entity_id, locale, version, field_name, content_html, status, published_at)
SELECT 'guide', g.id, g.locale, 2, 'body_html', g.body_html, 'published', NOW()
FROM seo_guides g
WHERE g.content_status = 'published'
  AND g.locale IN ('fr', 'ar')
ON CONFLICT (entity_type, entity_id, locale, field_name, version) DO UPDATE SET
  content_html = EXCLUDED.content_html,
  status = 'published',
  published_at = NOW();
