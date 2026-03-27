-- =============================================================================
-- Manual validation: one restaurant — source rows per Activation Health Score metric
-- Mirrors logic in models/marts/activation/mart_activation_health_score.sql
--
-- How to use:
-- 1. Find/replace the placeholder UUID in this file (every block repeats it).
-- 2. Run each block separately in DBeaver (select the block → execute).
-- 3. Compare sums / counts to thresholds in comments; compare points to the mart.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0) Restaurant row + “in mart cohort?” (base_restaurants filters)
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id  -- <<< find/replace UUID
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
)
SELECT
    '0_restaurant_cohort' AS section,
    r.id AS restaurant_id,
    r.inserted_at,
    r.deleted_at,
    r.is_blocked,
    r.email,
    r.trading_name,
    r.company_name,
    CASE
        WHEN r.deleted_at IS NOT NULL THEN FALSE
        WHEN r.is_blocked IS TRUE THEN FALSE
        WHEN r.email IS NOT NULL AND r.email ILIKE '%suflex%' THEN FALSE
        WHEN r.trading_name IS NOT NULL AND r.trading_name ILIKE ANY (ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%',
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]) THEN FALSE
        WHEN r.company_name IS NOT NULL AND r.company_name ILIKE ANY (ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%',
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]) THEN FALSE
        WHEN r.inserted_at < (SELECT start_30d FROM tw) THEN FALSE
        ELSE TRUE
    END AS passes_base_restaurants_filters
FROM restaurants r
CROSS JOIN params p
WHERE r.id = p.restaurant_id;


-- -----------------------------------------------------------------------------
-- 0b) Feature flags (which “qualified bases” the mart can use)
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
)
SELECT
    '0b_enable_feature' AS section,
    ef.restaurant_id,
    ef.count_products,
    ef.controlled_products,
    ef.production_tags
FROM enable_feature ef
CROSS JOIN params p
WHERE ef.restaurant_id = p.restaurant_id;


-- =============================================================================
-- SETUP
-- =============================================================================

-- -----------------------------------------------------------------------------
-- S1 — Gestor + colaborador login (source: access_history + authentications.role)
-- Rule: ≥1 restaurant_admin AND ≥1 restaurant_employee in last 30d (TTVW in mart = calendar 30d)
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
)
SELECT
    'S1_access_history' AS metric,
    ah.id AS access_history_id,
    ah.inserted_at,
    ah.login,
    ah.user_name,
    ah.platform,
    a.role AS authentication_role
FROM access_history ah
JOIN authentications a ON a.login = ah.login
CROSS JOIN params p
CROSS JOIN tw
WHERE (ah.restaurant_id::uuid) = p.restaurant_id
  AND ah.inserted_at >= tw.start_30d
  AND ah.restaurant_id IS NOT NULL
  AND ah.restaurant_id ~ '^[0-9a-fA-F-]{36}$'
ORDER BY ah.inserted_at;


-- S1 — quick roll-up (should match mart S1 hit)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
)
SELECT
    'S1_summary' AS metric,
    MAX(CASE WHEN a.role = 'restaurant_admin' THEN 1 ELSE 0 END) AS has_gestor,
    MAX(CASE WHEN a.role = 'restaurant_employee' THEN 1 ELSE 0 END) AS has_colaborador,
    CASE
        WHEN MAX(CASE WHEN a.role = 'restaurant_admin' THEN 1 ELSE 0 END) = 1
         AND MAX(CASE WHEN a.role = 'restaurant_employee' THEN 1 ELSE 0 END) = 1
        THEN 1 ELSE 0
    END AS hit_s1_logins
FROM access_history ah
JOIN authentications a ON a.login = ah.login
CROSS JOIN params p
CROSS JOIN tw
WHERE (ah.restaurant_id::uuid) = p.restaurant_id
  AND ah.inserted_at >= tw.start_30d
  AND ah.restaurant_id IS NOT NULL
  AND ah.restaurant_id ~ '^[0-9a-fA-F-]{36}$';


-- -----------------------------------------------------------------------------
-- S2 — ≥2 inventory lists each with ≥1 controlled product
-- Base: enable_feature.count_products = TRUE (mart: qualified_base_count)
-- Source: inventory_list, inventory_list_products, controlled_products
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'S2_list_with_controlled' AS metric,
    il.id AS inventory_list_id,
    il.inserted_at AS list_inserted_at,
    ilp.product_id,
    cp.id AS controlled_product_id
FROM inventory_list il
JOIN inventory_list_products ilp ON il.id = ilp.inventory_list_id
JOIN controlled_products cp ON cp.product_id = ilp.product_id AND cp.restaurant_id = il.restaurant_id
JOIN enable_feature ef ON ef.restaurant_id = il.restaurant_id AND ef.count_products = TRUE
CROSS JOIN p
WHERE il.restaurant_id = p.restaurant_id
ORDER BY il.id, ilp.product_id;


-- S2 — distinct qualifying lists count (mart: hit if ≥2)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'S2_summary' AS metric,
    COUNT(DISTINCT il.id) AS distinct_lists_with_at_least_one_controlled,
    CASE WHEN COUNT(DISTINCT il.id) >= 2 THEN 1 ELSE 0 END AS hit_s2
FROM inventory_list il
JOIN inventory_list_products ilp ON il.id = ilp.inventory_list_id
JOIN controlled_products cp ON cp.product_id = ilp.product_id AND cp.restaurant_id = il.restaurant_id
JOIN enable_feature ef ON ef.restaurant_id = il.restaurant_id AND ef.count_products = TRUE
CROSS JOIN p
WHERE il.restaurant_id = p.restaurant_id;


-- -----------------------------------------------------------------------------
-- S3 — ≥5 controlled products with product.weight > 0
-- Base: enable_feature.controlled_products = TRUE
-- Source: controlled_products + products
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'S3_controlled_product_row' AS metric,
    cp.id AS controlled_product_id,
    cp.product_id,
    pr.name AS product_name,
    COALESCE(pr.weight, 0) AS product_weight,
    (COALESCE(pr.weight, 0) > 0) AS counts_for_s3
FROM controlled_products cp
LEFT JOIN products pr ON pr.id = cp.product_id
JOIN enable_feature ef ON ef.restaurant_id = cp.restaurant_id AND ef.controlled_products = TRUE
CROSS JOIN p
WHERE cp.restaurant_id = p.restaurant_id
ORDER BY counts_for_s3 DESC, cp.id;


-- S3 — summary (counts / hit vs mart)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'S3_summary' AS metric,
    COUNT(DISTINCT cp.id) FILTER (WHERE COALESCE(pr.weight, 0) > 0) AS controlled_with_weight_cnt,
    CASE WHEN COUNT(DISTINCT cp.id) FILTER (WHERE COALESCE(pr.weight, 0) > 0) >= 5 THEN 1 ELSE 0 END AS hit_s3
FROM controlled_products cp
LEFT JOIN products pr ON pr.id = cp.product_id
JOIN enable_feature ef ON ef.restaurant_id = cp.restaurant_id AND ef.controlled_products = TRUE
CROSS JOIN p
WHERE cp.restaurant_id = p.restaurant_id;


-- =============================================================================
-- EFFORT (requires enable_feature.production_tags = TRUE for E1–E3)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- E1 — ≥50 prints (tag_infos + tag_infos_receivings, COALESCE(tags_count,1) per row)
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E1_tag_infos_production' AS metric,
    ti.id AS tag_info_id,
    ti.inserted_at,
    ti.product_id,
    ti.controlled_product,
    COALESCE(ti.tags_count, 1) AS print_units_this_row
FROM tag_infos ti
JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
CROSS JOIN p
CROSS JOIN tw
WHERE ti.restaurant_id = p.restaurant_id
  AND ti.inserted_at >= tw.start_30d
ORDER BY ti.inserted_at;


-- E1 — detail rows (tag_infos_receivings)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E1_tag_infos_receivings' AS metric,
    tr.id AS tag_info_receiving_id,
    tr.inserted_at,
    tr.product_id,
    tr.controlled_product,
    COALESCE(tr.tags_count, 1) AS print_units_this_row
FROM tag_infos_receivings tr
JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
CROSS JOIN p
CROSS JOIN tw
WHERE tr.restaurant_id = p.restaurant_id
  AND tr.inserted_at >= tw.start_30d
ORDER BY tr.inserted_at;


-- E1 — summary (total prints / hit vs mart)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E1_summary' AS metric,
    COALESCE((
        SELECT SUM(COALESCE(ti.tags_count, 1))
        FROM tag_infos ti
        JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
        WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= (SELECT start_30d FROM tw)
    ), 0)
    + COALESCE((
        SELECT SUM(COALESCE(tr.tags_count, 1))
        FROM tag_infos_receivings tr
        JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
        WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= (SELECT start_30d FROM tw)
    ), 0) AS total_print_units,
    CASE
        WHEN COALESCE((
            SELECT SUM(COALESCE(ti.tags_count, 1))
            FROM tag_infos ti
            JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
            WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= (SELECT start_30d FROM tw)
        ), 0)
        + COALESCE((
            SELECT SUM(COALESCE(tr.tags_count, 1))
            FROM tag_infos_receivings tr
            JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
            WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= (SELECT start_30d FROM tw)
        ), 0) >= 50
        THEN 1 ELSE 0
    END AS hit_e1
FROM p;


-- -----------------------------------------------------------------------------
-- E2 — ≥30 controlled prints (same tables; controlled_product = TRUE)
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E2_tag_infos_production_controlled' AS metric,
    ti.id AS tag_info_id,
    ti.inserted_at,
    ti.product_id,
    cp.id AS controlled_product_id,
    COALESCE(ti.tags_count, 1) AS print_units_this_row
FROM tag_infos ti
JOIN controlled_products cp
    ON cp.restaurant_id = ti.restaurant_id AND cp.product_id = ti.product_id
JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
CROSS JOIN p
CROSS JOIN tw
WHERE ti.restaurant_id = p.restaurant_id
  AND ti.inserted_at >= tw.start_30d
  AND ti.controlled_product = TRUE
ORDER BY ti.inserted_at;


-- E2 — detail rows (tag_infos_receivings, controlled)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E2_tag_infos_receivings_controlled' AS metric,
    tr.id,
    tr.inserted_at,
    tr.product_id,
    cp.id AS controlled_product_id,
    COALESCE(tr.tags_count, 1) AS print_units_this_row
FROM tag_infos_receivings tr
LEFT JOIN controlled_products cp
    ON cp.restaurant_id = tr.restaurant_id AND cp.product_id = tr.product_id
JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
CROSS JOIN p
CROSS JOIN tw
WHERE tr.restaurant_id = p.restaurant_id
  AND tr.inserted_at >= tw.start_30d
  AND tr.controlled_product = TRUE
ORDER BY tr.inserted_at;


-- E2 — summary (total controlled prints / hit vs mart)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E2_summary' AS metric,
    COALESCE((
        SELECT SUM(COALESCE(ti.tags_count, 1))
        FROM tag_infos ti
        JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
        WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= (SELECT start_30d FROM tw)
          AND ti.controlled_product = TRUE
    ), 0)
    + COALESCE((
        SELECT SUM(COALESCE(tr.tags_count, 1))
        FROM tag_infos_receivings tr
        JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
        WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= (SELECT start_30d FROM tw)
          AND tr.controlled_product = TRUE
    ), 0) AS total_controlled_print_units,
    CASE
        WHEN COALESCE((
            SELECT SUM(COALESCE(ti.tags_count, 1))
            FROM tag_infos ti
            JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
            WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= (SELECT start_30d FROM tw)
              AND ti.controlled_product = TRUE
        ), 0)
        + COALESCE((
            SELECT SUM(COALESCE(tr.tags_count, 1))
            FROM tag_infos_receivings tr
            JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
            WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= (SELECT start_30d FROM tw)
              AND tr.controlled_product = TRUE
        ), 0) >= 30
        THEN 1 ELSE 0
    END AS hit_e2
FROM p;


-- -----------------------------------------------------------------------------
-- E3 — ≥10 baixas (SUM tags_count_removed)
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E3_tag_infos_production_baixa' AS metric,
    ti.id,
    ti.inserted_at,
    ti.product_id,
    COALESCE(ti.tags_count_removed, 0) AS baixa_units_this_row
FROM tag_infos ti
JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
CROSS JOIN p
CROSS JOIN tw
WHERE ti.restaurant_id = p.restaurant_id
  AND ti.inserted_at >= tw.start_30d
  AND COALESCE(ti.tags_count_removed, 0) > 0
ORDER BY ti.inserted_at;


-- E3 — detail rows (tag_infos_receivings, baixa rows only)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E3_tag_infos_receivings_baixa' AS metric,
    tr.id,
    tr.inserted_at,
    tr.product_id,
    COALESCE(tr.tags_count_removed, 0) AS baixa_units_this_row
FROM tag_infos_receivings tr
JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
CROSS JOIN p
CROSS JOIN tw
WHERE tr.restaurant_id = p.restaurant_id
  AND tr.inserted_at >= tw.start_30d
  AND COALESCE(tr.tags_count_removed, 0) > 0
ORDER BY tr.inserted_at;


-- E3 — summary (total baixas / hit vs mart)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E3_summary' AS metric,
    COALESCE((
        SELECT SUM(COALESCE(ti.tags_count_removed, 0))
        FROM tag_infos ti
        JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
        WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= (SELECT start_30d FROM tw)
    ), 0)
    + COALESCE((
        SELECT SUM(COALESCE(tr.tags_count_removed, 0))
        FROM tag_infos_receivings tr
        JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
        WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= (SELECT start_30d FROM tw)
    ), 0) AS total_baixa_units,
    CASE
        WHEN COALESCE((
            SELECT SUM(COALESCE(ti.tags_count_removed, 0))
            FROM tag_infos ti
            JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
            WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= (SELECT start_30d FROM tw)
        ), 0)
        + COALESCE((
            SELECT SUM(COALESCE(tr.tags_count_removed, 0))
            FROM tag_infos_receivings tr
            JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
            WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= (SELECT start_30d FROM tw)
        ), 0) >= 10
        THEN 1 ELSE 0
    END AS hit_e3
FROM p;


-- -----------------------------------------------------------------------------
-- E4 — ≥5 completed contagens in last 30d (inventory.completed_at)
-- Base: enable_feature.count_products = TRUE
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E4_inventory_completed' AS metric,
    i.id AS inventory_id,
    i.inserted_at,
    i.completed_at,
    i.name AS inventory_name
FROM inventory i
JOIN enable_feature ef ON ef.restaurant_id = i.restaurant_id AND ef.count_products = TRUE
CROSS JOIN p
CROSS JOIN tw
WHERE i.restaurant_id = p.restaurant_id
  AND i.completed_at IS NOT NULL
  AND i.completed_at >= tw.start_30d
ORDER BY i.completed_at;


-- E4 — summary (completed contagens count / hit vs mart)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'E4_summary' AS metric,
    COUNT(*) AS completed_contagens_cnt,
    CASE WHEN COUNT(*) >= 5 THEN 1 ELSE 0 END AS hit_e4
FROM inventory i
JOIN enable_feature ef ON ef.restaurant_id = i.restaurant_id AND ef.count_products = TRUE
CROSS JOIN p
CROSS JOIN tw
WHERE i.restaurant_id = p.restaurant_id
  AND i.completed_at IS NOT NULL
  AND i.completed_at >= tw.start_30d;


-- =============================================================================
-- VALUE (V1–V4): value_metrics uses clean_base join; tag rows still need production_tags
-- for the tag-based sums. Prints/baixas only count if product is in restaurant_products
-- AND products.weight > 0 (shared catalog rule in mart).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- V1 — ≥20 weighted prints (any controlled flag) on shared products with weight
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'V1_tag_infos_production' AS metric,
    ti.id,
    ti.inserted_at,
    ti.product_id,
    ti.controlled_product,
    COALESCE(ti.tags_count, 1) AS print_units,
    rp.id AS restaurant_product_id,
    COALESCE(pr.weight, 0) AS product_weight
FROM tag_infos ti
JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
CROSS JOIN p
CROSS JOIN tw
WHERE ti.restaurant_id = p.restaurant_id
  AND ti.inserted_at >= tw.start_30d
ORDER BY ti.inserted_at;


-- V1 — detail rows (tag_infos_receivings + restaurant_products + weight)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'V1_tag_infos_receivings' AS metric,
    tr.id,
    tr.inserted_at,
    tr.product_id,
    tr.controlled_product,
    COALESCE(tr.tags_count, 1) AS print_units,
    rp.id AS restaurant_product_id,
    COALESCE(pr.weight, 0) AS product_weight
FROM tag_infos_receivings tr
JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
CROSS JOIN p
CROSS JOIN tw
WHERE tr.restaurant_id = p.restaurant_id
  AND tr.inserted_at >= tw.start_30d
ORDER BY tr.inserted_at;


-- V1 — summary (weighted print units / hit vs mart)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'V1_summary' AS metric,
    COALESCE((
        SELECT SUM(COALESCE(ti.tags_count, 1))
        FROM tag_infos ti
        JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
        JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
        JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
        WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= (SELECT start_30d FROM tw)
    ), 0)
    + COALESCE((
        SELECT SUM(COALESCE(tr.tags_count, 1))
        FROM tag_infos_receivings tr
        JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
        JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
        JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
        WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= (SELECT start_30d FROM tw)
    ), 0) AS total_weighted_print_units,
    CASE
        WHEN COALESCE((
            SELECT SUM(COALESCE(ti.tags_count, 1))
            FROM tag_infos ti
            JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
            JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
            JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
            WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= (SELECT start_30d FROM tw)
        ), 0)
        + COALESCE((
            SELECT SUM(COALESCE(tr.tags_count, 1))
            FROM tag_infos_receivings tr
            JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
            JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
            JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
            WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= (SELECT start_30d FROM tw)
        ), 0) >= 20
        THEN 1 ELSE 0
    END AS hit_v1
FROM p;


-- -----------------------------------------------------------------------------
-- V2 — ≥30 weighted controlled prints
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'V2_tag_infos_production' AS metric,
    ti.id,
    ti.inserted_at,
    ti.product_id,
    cp.id AS controlled_product_id,
    COALESCE(ti.tags_count, 1) AS print_units,
    COALESCE(pr.weight, 0) AS product_weight
FROM tag_infos ti
JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
JOIN controlled_products cp ON cp.restaurant_id = ti.restaurant_id AND cp.product_id = ti.product_id
JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
CROSS JOIN p
CROSS JOIN tw
WHERE ti.restaurant_id = p.restaurant_id
  AND ti.inserted_at >= tw.start_30d
  AND ti.controlled_product = TRUE
ORDER BY ti.inserted_at;


-- V2 — detail rows (tag_infos_receivings + weight; controlled only)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'V2_tag_infos_receivings' AS metric,
    tr.id,
    tr.inserted_at,
    tr.product_id,
    cp.id AS controlled_product_id,
    COALESCE(tr.tags_count, 1) AS print_units,
    COALESCE(pr.weight, 0) AS product_weight
FROM tag_infos_receivings tr
JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
JOIN controlled_products cp ON cp.restaurant_id = tr.restaurant_id AND cp.product_id = tr.product_id
JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
CROSS JOIN p
CROSS JOIN tw
WHERE tr.restaurant_id = p.restaurant_id
  AND tr.inserted_at >= tw.start_30d
  AND tr.controlled_product = TRUE
ORDER BY tr.inserted_at;


-- -----------------------------------------------------------------------------
-- V3 — ≥5 weighted baixas on controlled rows
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'V3_tag_infos_production' AS metric,
    ti.id,
    ti.inserted_at,
    ti.product_id,
    cp.id AS controlled_product_id,
    COALESCE(ti.tags_count_removed, 0) AS baixa_units,
    COALESCE(pr.weight, 0) AS product_weight
FROM tag_infos ti
JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
JOIN controlled_products cp ON cp.restaurant_id = ti.restaurant_id AND cp.product_id = ti.product_id
JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
CROSS JOIN p
CROSS JOIN tw
WHERE ti.restaurant_id = p.restaurant_id
  AND ti.inserted_at >= tw.start_30d
  AND ti.controlled_product = TRUE
  AND COALESCE(ti.tags_count_removed, 0) > 0
ORDER BY ti.inserted_at;


-- V3 — detail rows (tag_infos_receivings + weight; baixa rows only)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'V3_tag_infos_receivings' AS metric,
    tr.id,
    tr.inserted_at,
    tr.product_id,
    cp.id AS controlled_product_id,
    COALESCE(tr.tags_count_removed, 0) AS baixa_units,
    COALESCE(pr.weight, 0) AS product_weight
FROM tag_infos_receivings tr
JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
JOIN controlled_products cp ON cp.restaurant_id = tr.restaurant_id AND cp.product_id = tr.product_id
JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
CROSS JOIN p
CROSS JOIN tw
WHERE tr.restaurant_id = p.restaurant_id
  AND tr.inserted_at >= tw.start_30d
  AND tr.controlled_product = TRUE
  AND COALESCE(tr.tags_count_removed, 0) > 0
ORDER BY tr.inserted_at;


-- -----------------------------------------------------------------------------
-- V4 — ≥2 distinct completed inventories that include ≥1 line counted with
-- weighted controlled product (inventory + inventory_count + controlled_products + products)
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params),
qual AS (
    SELECT i.id AS inventory_id,
           i.completed_at,
           ic.id AS inventory_count_id,
           ic.product_id,
           cp.id AS controlled_product_id,
           COALESCE(pr.weight, 0) AS product_weight
    FROM inventory i
    JOIN enable_feature ef ON ef.restaurant_id = i.restaurant_id AND ef.count_products = TRUE
    JOIN inventory_count ic ON ic.inventory_id = i.id
    JOIN controlled_products cp ON cp.restaurant_id = i.restaurant_id AND cp.product_id = ic.product_id
    JOIN products pr ON pr.id = cp.product_id AND COALESCE(pr.weight, 0) > 0
    CROSS JOIN p
    CROSS JOIN tw
    WHERE i.restaurant_id = p.restaurant_id
      AND i.completed_at IS NOT NULL
      AND i.completed_at >= tw.start_30d
)
SELECT
    'V4_inventory_line' AS metric,
    q.inventory_id,
    q.completed_at,
    q.inventory_count_id,
    q.product_id,
    q.controlled_product_id,
    q.product_weight
FROM qual q
ORDER BY q.completed_at, q.inventory_id;


-- V4 — summary (distinct inventories / hit vs mart)
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params)
SELECT
    'V4_summary' AS metric,
    COUNT(DISTINCT i.id) AS distinct_inventories_with_weighted_controlled_line,
    CASE WHEN COUNT(DISTINCT i.id) >= 2 THEN 1 ELSE 0 END AS hit_v4
FROM inventory i
JOIN enable_feature ef ON ef.restaurant_id = i.restaurant_id AND ef.count_products = TRUE
JOIN inventory_count ic ON ic.inventory_id = i.id
JOIN controlled_products cp ON cp.restaurant_id = i.restaurant_id AND cp.product_id = ic.product_id
JOIN products pr ON pr.id = cp.product_id AND COALESCE(pr.weight, 0) > 0
CROSS JOIN p
CROSS JOIN tw
WHERE i.restaurant_id = p.restaurant_id
  AND i.completed_at IS NOT NULL
  AND i.completed_at >= tw.start_30d;


-- -----------------------------------------------------------------------------
-- Key (mart: has_weighted_controlled_core_action) — V2 ≥30 OR V3 ≥5 OR V4 ≥2
-- Same joins/thresholds as value_metrics in mart_activation_health_score.sql
-- -----------------------------------------------------------------------------
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id
),
tw AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_30d
),
p AS (SELECT restaurant_id FROM params),
v2 AS (
    SELECT
        COALESCE((
            SELECT SUM(COALESCE(ti.tags_count, 1))
            FROM tag_infos ti
            JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
            JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
            JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
            CROSS JOIN p
            CROSS JOIN tw
            WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= tw.start_30d AND ti.controlled_product = TRUE
        ), 0)
        + COALESCE((
            SELECT SUM(COALESCE(tr.tags_count, 1))
            FROM tag_infos_receivings tr
            JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
            JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
            JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
            CROSS JOIN p
            CROSS JOIN tw
            WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= tw.start_30d AND tr.controlled_product = TRUE
        ), 0) AS weighted_controlled_print_units
    FROM p
),
v3 AS (
    SELECT
        COALESCE((
            SELECT SUM(COALESCE(ti.tags_count_removed, 0))
            FROM tag_infos ti
            JOIN enable_feature ef ON ef.restaurant_id = ti.restaurant_id AND ef.production_tags = TRUE
            JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
            JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
            CROSS JOIN p
            CROSS JOIN tw
            WHERE ti.restaurant_id = p.restaurant_id AND ti.inserted_at >= tw.start_30d AND ti.controlled_product = TRUE
        ), 0)
        + COALESCE((
            SELECT SUM(COALESCE(tr.tags_count_removed, 0))
            FROM tag_infos_receivings tr
            JOIN enable_feature ef ON ef.restaurant_id = tr.restaurant_id AND ef.production_tags = TRUE
            JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
            JOIN products pr ON pr.id = rp.product_id AND COALESCE(pr.weight, 0) > 0
            CROSS JOIN p
            CROSS JOIN tw
            WHERE tr.restaurant_id = p.restaurant_id AND tr.inserted_at >= tw.start_30d AND tr.controlled_product = TRUE
        ), 0) AS weighted_controlled_baixa_units
    FROM p
),
v4 AS (
    SELECT
        COUNT(DISTINCT i.id) AS distinct_inventories
    FROM inventory i
    JOIN enable_feature ef ON ef.restaurant_id = i.restaurant_id AND ef.count_products = TRUE
    JOIN inventory_count ic ON ic.inventory_id = i.id
    JOIN controlled_products cp ON cp.restaurant_id = i.restaurant_id AND cp.product_id = ic.product_id
    JOIN products pr ON pr.id = cp.product_id AND COALESCE(pr.weight, 0) > 0
    CROSS JOIN p
    CROSS JOIN tw
    WHERE i.restaurant_id = p.restaurant_id
      AND i.completed_at IS NOT NULL
      AND i.completed_at >= tw.start_30d
)
SELECT
    'Key_summary' AS metric,
    v2.weighted_controlled_print_units,
    CASE WHEN v2.weighted_controlled_print_units >= 30 THEN 1 ELSE 0 END AS hit_v2_key,
    v3.weighted_controlled_baixa_units,
    CASE WHEN v3.weighted_controlled_baixa_units >= 5 THEN 1 ELSE 0 END AS hit_v3_key,
    v4.distinct_inventories,
    CASE WHEN v4.distinct_inventories >= 2 THEN 1 ELSE 0 END AS hit_v4_key,
    CASE
        WHEN v2.weighted_controlled_print_units >= 30
          OR v3.weighted_controlled_baixa_units >= 5
          OR v4.distinct_inventories >= 2
        THEN 1
        ELSE 0
    END AS has_weighted_controlled_core_action
FROM v2
CROSS JOIN v3
CROSS JOIN v4;
