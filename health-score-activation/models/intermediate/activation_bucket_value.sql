-- Activation Health Score – Value Bucket (Intermediate Model)
--
-- One row per restaurant that has at least one Value metric (V1–V4).
-- Does NOT define the cohort; consolidation defines base_restaurants and LEFT JOINs this.
-- Outputs: restaurant_id, V1–V4 hit flags + has_weighted_controlled_core_action (Key).
-- Weight: via restaurant_products + products (playbook: shared products).
-- Logic from viability_tests/activation_value_metrics.sql (V1–V4 per-restaurant).

WITH hygiene_restaurant_ids AS (
    SELECT r.id
    FROM restaurants r
    WHERE r.deleted_at IS NULL
      AND r.is_blocked IS FALSE
      AND (r.email IS NULL OR r.email NOT ILIKE '%suflex%')
      AND (r.trading_name IS NULL OR r.trading_name NOT ILIKE ALL (ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%',
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
      ]))
      AND (r.company_name IS NULL OR r.company_name NOT ILIKE ALL (ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%',
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
      ]))
),

qualified_base AS (
    SELECT h.id
    FROM hygiene_restaurant_ids h
    JOIN enable_feature ef ON ef.restaurant_id = h.id
    WHERE ef.production_tags = TRUE
),

qualified_base_count AS (
    SELECT h.id
    FROM hygiene_restaurant_ids h
    JOIN enable_feature ef ON ef.restaurant_id = h.id
    WHERE ef.count_products = TRUE
),

-- V1: 20 impressões com peso
v1_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti ON ti.restaurant_id = qb.id AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),
v1_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr ON tr.restaurant_id = qb.id AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),

-- V2: 30 impressões controladas com peso
v2_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti ON ti.restaurant_id = qb.id AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND ti.controlled_product = TRUE
    JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),
v2_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr ON tr.restaurant_id = qb.id AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tr.controlled_product = TRUE
    JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),

-- V3: 5 baixas controladas com peso
v3_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti ON ti.restaurant_id = qb.id AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND ti.controlled_product = TRUE
    JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),
v3_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr ON tr.restaurant_id = qb.id AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tr.controlled_product = TRUE
    JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),

-- V4: 2 contagens com ≥1 produto controlado com peso
inventories_with_controlled_weight AS (
    SELECT i.restaurant_id, i.id AS inventory_id
    FROM qualified_base_count qb
    JOIN inventory i ON i.restaurant_id = qb.id AND i.completed_at IS NOT NULL AND i.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN inventory_count ic ON ic.inventory_id = i.id
    JOIN controlled_products cp ON cp.restaurant_id = i.restaurant_id AND cp.product_id = ic.product_id
    JOIN products p ON p.id = cp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY i.restaurant_id, i.id
),
v4_per_restaurant AS (
    SELECT restaurant_id, COUNT(DISTINCT inventory_id) AS cnt
    FROM inventories_with_controlled_weight
    GROUP BY restaurant_id
),

all_restaurant_ids AS (
    SELECT restaurant_id FROM v1_production
    UNION
    SELECT restaurant_id FROM v1_receivings
    UNION
    SELECT restaurant_id FROM v2_production
    UNION
    SELECT restaurant_id FROM v2_receivings
    UNION
    SELECT restaurant_id FROM v3_production
    UNION
    SELECT restaurant_id FROM v3_receivings
    UNION
    SELECT restaurant_id FROM v4_per_restaurant
)

SELECT
    a.restaurant_id,
    (COALESCE(v1p.cnt, 0) + COALESCE(v1r.cnt, 0)) AS v1_prints_with_weight_cnt,
    CASE WHEN (COALESCE(v1p.cnt, 0) + COALESCE(v1r.cnt, 0)) >= 20 THEN 1 ELSE 0 END AS hit_v1_20_prints_weight,
    (COALESCE(v2p.cnt, 0) + COALESCE(v2r.cnt, 0)) AS v2_controlled_weight_cnt,
    CASE WHEN (COALESCE(v2p.cnt, 0) + COALESCE(v2r.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_v2_30_controlled_weight,
    (COALESCE(v3p.cnt, 0) + COALESCE(v3r.cnt, 0)) AS v3_baixas_controlled_weight_cnt,
    CASE WHEN (COALESCE(v3p.cnt, 0) + COALESCE(v3r.cnt, 0)) >= 5 THEN 1 ELSE 0 END AS hit_v3_5_baixas_controlled_weight,
    COALESCE(v4.cnt, 0) AS v4_contagens_controlled_weight_cnt,
    CASE WHEN COALESCE(v4.cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_v4_2_contagens_controlled_weight,
    CASE
        WHEN (COALESCE(v2p.cnt, 0) + COALESCE(v2r.cnt, 0)) >= 30
          OR (COALESCE(v3p.cnt, 0) + COALESCE(v3r.cnt, 0)) >= 5
          OR COALESCE(v4.cnt, 0) >= 2
        THEN 1
        ELSE 0
    END AS has_weighted_controlled_core_action
FROM all_restaurant_ids a
LEFT JOIN v1_production v1p ON a.restaurant_id = v1p.restaurant_id
LEFT JOIN v1_receivings v1r ON a.restaurant_id = v1r.restaurant_id
LEFT JOIN v2_production v2p ON a.restaurant_id = v2p.restaurant_id
LEFT JOIN v2_receivings v2r ON a.restaurant_id = v2r.restaurant_id
LEFT JOIN v3_production v3p ON a.restaurant_id = v3p.restaurant_id
LEFT JOIN v3_receivings v3r ON a.restaurant_id = v3r.restaurant_id
LEFT JOIN v4_per_restaurant v4 ON a.restaurant_id = v4.restaurant_id;
