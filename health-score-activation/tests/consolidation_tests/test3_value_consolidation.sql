-- =============================================================================
-- Test 3: Value + Consolidation
-- Same cohort in both steps. Compare pts_v1..v4 and has_weighted_controlled_core_action; they must match.
-- Step 2: run models/marts/activation/mart_activation_health_score.sql separately.
-- Run Step 1, then Step 2, then Step 3 to get mismatches (0 rows = pass).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Step 1: Value points for cohort only (same cohort & column names as Step 2)
-- Output: one row per cohort restaurant, Value point columns + Key.
-- -----------------------------------------------------------------------------

WITH base_restaurants AS (
    SELECT r.id AS restaurant_id
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
      AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
),

clean_base AS (
    SELECT restaurant_id AS id FROM base_restaurants
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.production_tags = TRUE
),

qualified_base_count AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.count_products = TRUE
),

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
value_metrics AS (
    SELECT
        cb.id AS restaurant_id,
        CASE WHEN (COALESCE(v1p.cnt, 0) + COALESCE(v1r.cnt, 0)) >= 20 THEN 1 ELSE 0 END AS hit_v1_20_prints_weight,
        CASE WHEN (COALESCE(v2p.cnt, 0) + COALESCE(v2r.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_v2_30_controlled_weight,
        CASE WHEN (COALESCE(v3p.cnt, 0) + COALESCE(v3r.cnt, 0)) >= 5 THEN 1 ELSE 0 END AS hit_v3_5_baixas_controlled_weight,
        CASE WHEN COALESCE(v4.cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_v4_2_contagens_controlled_weight,
        CASE
            WHEN (COALESCE(v2p.cnt, 0) + COALESCE(v2r.cnt, 0)) >= 30
              OR (COALESCE(v3p.cnt, 0) + COALESCE(v3r.cnt, 0)) >= 5
              OR COALESCE(v4.cnt, 0) >= 2
            THEN 1
            ELSE 0
        END AS has_weighted_controlled_core_action
    FROM clean_base cb
    LEFT JOIN v1_production v1p ON cb.id = v1p.restaurant_id
    LEFT JOIN v1_receivings v1r ON cb.id = v1r.restaurant_id
    LEFT JOIN v2_production v2p ON cb.id = v2p.restaurant_id
    LEFT JOIN v2_receivings v2r ON cb.id = v2r.restaurant_id
    LEFT JOIN v3_production v3p ON cb.id = v3p.restaurant_id
    LEFT JOIN v3_receivings v3r ON cb.id = v3r.restaurant_id
    LEFT JOIN v4_per_restaurant v4 ON cb.id = v4.restaurant_id
)

SELECT
    b.restaurant_id,
    COALESCE(v.hit_v1_20_prints_weight, 0) * 15 AS pts_v1_20_prints_weight,
    COALESCE(v.hit_v2_30_controlled_weight, 0) * 10 AS pts_v2_30_controlled_weight,
    COALESCE(v.hit_v3_5_baixas_controlled_weight, 0) * 25 AS pts_v3_5_baixas_controlled_weight,
    COALESCE(v.hit_v4_2_contagens_controlled_weight, 0) * 10 AS pts_v4_2_contagens_controlled_weight,
    COALESCE(v.has_weighted_controlled_core_action, 0) AS has_weighted_controlled_core_action
FROM base_restaurants b
LEFT JOIN value_metrics v ON b.restaurant_id = v.restaurant_id;


-- -----------------------------------------------------------------------------
-- Step 2: Full consolidation (all buckets)
-- Run in DBeaver: models/marts/activation/mart_activation_health_score.sql
-- Check: same cohort; Value columns + Key; EXPLAIN cost < 500k.
-- -----------------------------------------------------------------------------
-- (Execute the mart file separately.)


-- -----------------------------------------------------------------------------
-- Step 3: Comparison — do Value points and Key match between Step 1 and Step 2?
-- Runs Step 1 and duplicate Value logic; 0 rows = pass.
-- -----------------------------------------------------------------------------

WITH
step1 AS MATERIALIZED (
    WITH base_restaurants AS (
        SELECT r.id AS restaurant_id
        FROM restaurants r
        WHERE r.deleted_at IS NULL AND r.is_blocked IS FALSE
          AND (r.email IS NULL OR r.email NOT ILIKE '%suflex%')
          AND (r.trading_name IS NULL OR r.trading_name NOT ILIKE ALL (ARRAY['%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%']))
          AND (r.company_name IS NULL OR r.company_name NOT ILIKE ALL (ARRAY['%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%']))
          AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    ),
    clean_base AS (SELECT restaurant_id AS id FROM base_restaurants),
    qualified_base AS (
        SELECT cb.id FROM clean_base cb JOIN enable_feature ef ON cb.id = ef.restaurant_id WHERE ef.production_tags = TRUE
    ),
    qualified_base_count AS (
        SELECT cb.id FROM clean_base cb JOIN enable_feature ef ON cb.id = ef.restaurant_id WHERE ef.count_products = TRUE
    ),
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
    value_metrics AS (
        SELECT
            cb.id AS restaurant_id,
            CASE WHEN (COALESCE(v1p.cnt, 0) + COALESCE(v1r.cnt, 0)) >= 20 THEN 1 ELSE 0 END AS hit_v1_20_prints_weight,
            CASE WHEN (COALESCE(v2p.cnt, 0) + COALESCE(v2r.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_v2_30_controlled_weight,
            CASE WHEN (COALESCE(v3p.cnt, 0) + COALESCE(v3r.cnt, 0)) >= 5 THEN 1 ELSE 0 END AS hit_v3_5_baixas_controlled_weight,
            CASE WHEN COALESCE(v4.cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_v4_2_contagens_controlled_weight,
            CASE
                WHEN (COALESCE(v2p.cnt, 0) + COALESCE(v2r.cnt, 0)) >= 30
                  OR (COALESCE(v3p.cnt, 0) + COALESCE(v3r.cnt, 0)) >= 5
                  OR COALESCE(v4.cnt, 0) >= 2
                THEN 1
                ELSE 0
            END AS has_weighted_controlled_core_action
        FROM clean_base cb
        LEFT JOIN v1_production v1p ON cb.id = v1p.restaurant_id
        LEFT JOIN v1_receivings v1r ON cb.id = v1r.restaurant_id
        LEFT JOIN v2_production v2p ON cb.id = v2p.restaurant_id
        LEFT JOIN v2_receivings v2r ON cb.id = v2r.restaurant_id
        LEFT JOIN v3_production v3p ON cb.id = v3p.restaurant_id
        LEFT JOIN v3_receivings v3r ON cb.id = v3r.restaurant_id
        LEFT JOIN v4_per_restaurant v4 ON cb.id = v4.restaurant_id
    )
    SELECT
        b.restaurant_id,
        COALESCE(v.hit_v1_20_prints_weight, 0) * 15 AS pts_v1_20_prints_weight,
        COALESCE(v.hit_v2_30_controlled_weight, 0) * 10 AS pts_v2_30_controlled_weight,
        COALESCE(v.hit_v3_5_baixas_controlled_weight, 0) * 25 AS pts_v3_5_baixas_controlled_weight,
        COALESCE(v.hit_v4_2_contagens_controlled_weight, 0) * 10 AS pts_v4_2_contagens_controlled_weight,
        COALESCE(v.has_weighted_controlled_core_action, 0) AS has_weighted_controlled_core_action
    FROM base_restaurants b
    LEFT JOIN value_metrics v ON b.restaurant_id = v.restaurant_id
),

step2_value_cols AS MATERIALIZED (
    WITH base_restaurants AS (
        SELECT r.id AS restaurant_id
        FROM restaurants r
        WHERE r.deleted_at IS NULL AND r.is_blocked IS FALSE
          AND (r.email IS NULL OR r.email NOT ILIKE '%suflex%')
          AND (r.trading_name IS NULL OR r.trading_name NOT ILIKE ALL (ARRAY['%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%']))
          AND (r.company_name IS NULL OR r.company_name NOT ILIKE ALL (ARRAY['%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%']))
          AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    ),
    clean_base AS (SELECT restaurant_id AS id FROM base_restaurants),
    qualified_base AS (
        SELECT cb.id FROM clean_base cb JOIN enable_feature ef ON cb.id = ef.restaurant_id WHERE ef.production_tags = TRUE
    ),
    qualified_base_count AS (
        SELECT cb.id FROM clean_base cb JOIN enable_feature ef ON cb.id = ef.restaurant_id WHERE ef.count_products = TRUE
    ),
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
    value_metrics AS (
        SELECT
            cb.id AS restaurant_id,
            CASE WHEN (COALESCE(v1p.cnt, 0) + COALESCE(v1r.cnt, 0)) >= 20 THEN 1 ELSE 0 END AS hit_v1_20_prints_weight,
            CASE WHEN (COALESCE(v2p.cnt, 0) + COALESCE(v2r.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_v2_30_controlled_weight,
            CASE WHEN (COALESCE(v3p.cnt, 0) + COALESCE(v3r.cnt, 0)) >= 5 THEN 1 ELSE 0 END AS hit_v3_5_baixas_controlled_weight,
            CASE WHEN COALESCE(v4.cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_v4_2_contagens_controlled_weight,
            CASE
                WHEN (COALESCE(v2p.cnt, 0) + COALESCE(v2r.cnt, 0)) >= 30
                  OR (COALESCE(v3p.cnt, 0) + COALESCE(v3r.cnt, 0)) >= 5
                  OR COALESCE(v4.cnt, 0) >= 2
                THEN 1
                ELSE 0
            END AS has_weighted_controlled_core_action
        FROM clean_base cb
        LEFT JOIN v1_production v1p ON cb.id = v1p.restaurant_id
        LEFT JOIN v1_receivings v1r ON cb.id = v1r.restaurant_id
        LEFT JOIN v2_production v2p ON cb.id = v2p.restaurant_id
        LEFT JOIN v2_receivings v2r ON cb.id = v2r.restaurant_id
        LEFT JOIN v3_production v3p ON cb.id = v3p.restaurant_id
        LEFT JOIN v3_receivings v3r ON cb.id = v3r.restaurant_id
        LEFT JOIN v4_per_restaurant v4 ON cb.id = v4.restaurant_id
    )
    SELECT
        b.restaurant_id,
        COALESCE(v.hit_v1_20_prints_weight, 0) * 15 AS pts_v1_20_prints_weight,
        COALESCE(v.hit_v2_30_controlled_weight, 0) * 10 AS pts_v2_30_controlled_weight,
        COALESCE(v.hit_v3_5_baixas_controlled_weight, 0) * 25 AS pts_v3_5_baixas_controlled_weight,
        COALESCE(v.hit_v4_2_contagens_controlled_weight, 0) * 10 AS pts_v4_2_contagens_controlled_weight,
        COALESCE(v.has_weighted_controlled_core_action, 0) AS has_weighted_controlled_core_action
    FROM base_restaurants b
    LEFT JOIN value_metrics v ON b.restaurant_id = v.restaurant_id
)

SELECT
    'MISMATCH' AS status,
    a.restaurant_id,
    a.pts_v1_20_prints_weight AS step1_v1,
    b.pts_v1_20_prints_weight AS step2_v1,
    a.pts_v2_30_controlled_weight AS step1_v2,
    b.pts_v2_30_controlled_weight AS step2_v2,
    a.pts_v3_5_baixas_controlled_weight AS step1_v3,
    b.pts_v3_5_baixas_controlled_weight AS step2_v3,
    a.pts_v4_2_contagens_controlled_weight AS step1_v4,
    b.pts_v4_2_contagens_controlled_weight AS step2_v4,
    a.has_weighted_controlled_core_action AS step1_key,
    b.has_weighted_controlled_core_action AS step2_key
FROM step1 a
JOIN step2_value_cols b ON a.restaurant_id = b.restaurant_id
WHERE a.pts_v1_20_prints_weight IS DISTINCT FROM b.pts_v1_20_prints_weight
   OR a.pts_v2_30_controlled_weight IS DISTINCT FROM b.pts_v2_30_controlled_weight
   OR a.pts_v3_5_baixas_controlled_weight IS DISTINCT FROM b.pts_v3_5_baixas_controlled_weight
   OR a.pts_v4_2_contagens_controlled_weight IS DISTINCT FROM b.pts_v4_2_contagens_controlled_weight
   OR a.has_weighted_controlled_core_action IS DISTINCT FROM b.has_weighted_controlled_core_action;
-- 0 rows = Test 3 pass.
