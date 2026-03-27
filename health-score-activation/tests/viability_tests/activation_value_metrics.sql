-- Activation – Value Capture Bucket Metrics (Viability Queries)
--
-- Run with or without EXPLAIN in DBeaver to validate feasibility of Value
-- milestones. Same format as activation_effort_metrics.sql: one metric at a time,
-- each with (1) viability/aggregate query and (2) per-restaurant query.
--
-- Base for V1–V3: qualified_base (production_tags). Base for V4: qualified_base_count (count_products). Weight: per playbook
-- "Shared products" rule, join via restaurant_products + restaurant_id so
-- we only count products linked to that restaurant; then products.weight > 0.

/* ============================================================================
   Metric V1 – 20 impressões com peso (15 pts)
   ---------------------------------------------------------------------------
   Prints (tag_infos + tag_infos_receivings) where product has weight > 0 and
   is linked to the restaurant via restaurant_products (playbook: shared products).
   Drive from qualified_base, 30-day window.
   ==========================================================================*/

EXPLAIN
WITH clean_base AS (
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
      AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.production_tags = TRUE
),

prints_with_weight_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti
      ON ti.restaurant_id = qb.id
      AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN restaurant_products rp
      ON rp.product_id = ti.product_id
      AND rp.restaurant_id = ti.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),

prints_with_weight_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr
      ON tr.restaurant_id = qb.id
      AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN restaurant_products rp
      ON rp.product_id = tr.product_id
      AND rp.restaurant_id = tr.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
)

SELECT
    COUNT(qb.id) AS "Base (Impressão Habilitada)",
    COUNT(*) FILTER (WHERE (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) >= 1) AS "Rests com ≥1 impressão com peso",
    COUNT(*) FILTER (WHERE (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) >= 20) AS "Rests com ≥20 impressões com peso",
    ROUND(
        (COUNT(*) FILTER (WHERE (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) >= 20)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥20 com peso)"
FROM qualified_base qb
LEFT JOIN prints_with_weight_production pw ON qb.id = pw.restaurant_id
LEFT JOIN prints_with_weight_receivings  pr ON qb.id = pr.restaurant_id;


/* ============================================================================
   Metric V1 – per-restaurant (for consolidation)
   ==========================================================================*/

WITH clean_base AS (
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
      AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.production_tags = TRUE
),

prints_with_weight_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti ON ti.restaurant_id = qb.id AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),

prints_with_weight_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr ON tr.restaurant_id = qb.id AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
)

SELECT
    qb.id AS restaurant_id,
    (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) AS prints_with_weight_cnt,
    CASE WHEN (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) >= 20 THEN 1 ELSE 0 END AS hit_v1_20_prints_weight
FROM qualified_base qb
LEFT JOIN prints_with_weight_production pw ON qb.id = pw.restaurant_id
LEFT JOIN prints_with_weight_receivings  pr ON qb.id = pr.restaurant_id;


/* ============================================================================
   Metric V2 – 30 impressões de produtos controlados com peso (10 pts)
   ---------------------------------------------------------------------------
   Same as V1 but only rows where controlled_product = TRUE. Drive from
   qualified_base, 30-day window; join via restaurant_products + products.weight.
   ==========================================================================*/

EXPLAIN
WITH clean_base AS (
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
      AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.production_tags = TRUE
),

controlled_weight_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti
      ON ti.restaurant_id = qb.id
      AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
      AND ti.controlled_product = TRUE
    JOIN restaurant_products rp
      ON rp.product_id = ti.product_id
      AND rp.restaurant_id = ti.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),

controlled_weight_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr
      ON tr.restaurant_id = qb.id
      AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
      AND tr.controlled_product = TRUE
    JOIN restaurant_products rp
      ON rp.product_id = tr.product_id
      AND rp.restaurant_id = tr.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
)

SELECT
    COUNT(qb.id) AS "Base (Impressão Habilitada)",
    COUNT(*) FILTER (WHERE (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) >= 1) AS "Rests com ≥1 impressão controlada com peso",
    COUNT(*) FILTER (WHERE (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30) AS "Rests com ≥30 impressões controladas com peso",
    ROUND(
        (COUNT(*) FILTER (WHERE (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥30 controladas com peso)"
FROM qualified_base qb
LEFT JOIN controlled_weight_production pw ON qb.id = pw.restaurant_id
LEFT JOIN controlled_weight_receivings  pr ON qb.id = pr.restaurant_id;


/* ============================================================================
   Metric V2 – per-restaurant (for consolidation)
   ==========================================================================*/

WITH clean_base AS (
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
      AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.production_tags = TRUE
),

controlled_weight_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti ON ti.restaurant_id = qb.id AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND ti.controlled_product = TRUE
    JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),

controlled_weight_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr ON tr.restaurant_id = qb.id AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tr.controlled_product = TRUE
    JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
)

SELECT
    qb.id AS restaurant_id,
    (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) AS controlled_weight_prints_cnt,
    CASE WHEN (COALESCE(pw.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_v2_30_controlled_weight
FROM qualified_base qb
LEFT JOIN controlled_weight_production pw ON qb.id = pw.restaurant_id
LEFT JOIN controlled_weight_receivings  pr ON qb.id = pr.restaurant_id;


/* ============================================================================
   Metric V3 – 5 baixas de etiquetas de produtos controlados com peso (25 pts)
   ---------------------------------------------------------------------------
   Baixas = tags_count_removed in tag_infos + tag_infos_receivings. Only rows
   where controlled_product = TRUE and product has weight (via restaurant_products).
   Drive from qualified_base, 30-day window.
   ==========================================================================*/

EXPLAIN
WITH clean_base AS (
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
      AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.production_tags = TRUE
),

baixas_controlled_weight_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti
      ON ti.restaurant_id = qb.id
      AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
      AND ti.controlled_product = TRUE
    JOIN restaurant_products rp
      ON rp.product_id = ti.product_id
      AND rp.restaurant_id = ti.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),

baixas_controlled_weight_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr
      ON tr.restaurant_id = qb.id
      AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
      AND tr.controlled_product = TRUE
    JOIN restaurant_products rp
      ON rp.product_id = tr.product_id
      AND rp.restaurant_id = tr.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
)

SELECT
    COUNT(qb.id) AS "Base (Impressão Habilitada)",
    COUNT(*) FILTER (WHERE (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 1) AS "Rests com ≥1 baixa controlada com peso",
    COUNT(*) FILTER (WHERE (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 5) AS "Rests com ≥5 baixas controladas com peso",
    ROUND(
        (COUNT(*) FILTER (WHERE (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 5)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥5 baixas controladas com peso)"
FROM qualified_base qb
LEFT JOIN baixas_controlled_weight_production bp ON qb.id = bp.restaurant_id
LEFT JOIN baixas_controlled_weight_receivings  br ON qb.id = br.restaurant_id;


/* ============================================================================
   Metric V3 – per-restaurant (for consolidation)
   ==========================================================================*/

WITH clean_base AS (
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
      AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.production_tags = TRUE
),

baixas_controlled_weight_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti ON ti.restaurant_id = qb.id AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND ti.controlled_product = TRUE
    JOIN restaurant_products rp ON rp.product_id = ti.product_id AND rp.restaurant_id = ti.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
),

baixas_controlled_weight_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr ON tr.restaurant_id = qb.id AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tr.controlled_product = TRUE
    JOIN restaurant_products rp ON rp.product_id = tr.product_id AND rp.restaurant_id = tr.restaurant_id
    JOIN products p ON p.id = rp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY qb.id
)

SELECT
    qb.id AS restaurant_id,
    (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) AS baixas_controlled_weight_cnt,
    CASE WHEN (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 5 THEN 1 ELSE 0 END AS hit_v3_5_baixas_controlled_weight
FROM qualified_base qb
LEFT JOIN baixas_controlled_weight_production bp ON qb.id = bp.restaurant_id
LEFT JOIN baixas_controlled_weight_receivings  br ON qb.id = br.restaurant_id;


/* ============================================================================
   Metric V4 – 2 contagens com ≥ 1 produto controlado com peso cada (10 pts)
   ---------------------------------------------------------------------------
   One "contagem" = one completed inventory (completed_at in last 30 days).
   Count distinct inventories that have ≥1 inventory_count row where the product
   is in controlled_products for that restaurant and has products.weight > 0.
   Base: qualified_base_count (count_products = TRUE). Ref: E4, counting ref.
   ==========================================================================*/

EXPLAIN
WITH clean_base AS (
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
      AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
),

qualified_base_count AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.count_products = TRUE
),

-- Completed inventories in window that have ≥1 count row with a controlled product with weight
inventories_with_controlled_weight AS (
    SELECT i.restaurant_id, i.id AS inventory_id
    FROM qualified_base_count qb
    JOIN inventory i
      ON i.restaurant_id = qb.id
      AND i.completed_at IS NOT NULL
      AND i.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN inventory_count ic ON ic.inventory_id = i.id
    JOIN controlled_products cp
      ON cp.restaurant_id = i.restaurant_id
      AND cp.product_id = ic.product_id
    JOIN products p ON p.id = cp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY i.restaurant_id, i.id
),

contagens_controlled_weight_per_restaurant AS (
    SELECT restaurant_id, COUNT(DISTINCT inventory_id) AS cnt
    FROM inventories_with_controlled_weight
    GROUP BY restaurant_id
)

SELECT
    COUNT(qb.id) AS "Base (Contagem Habilitada)",
    COUNT(*) FILTER (WHERE COALESCE(c.cnt, 0) >= 1) AS "Rests com ≥1 contagem com controlado+peso",
    COUNT(*) FILTER (WHERE COALESCE(c.cnt, 0) >= 2) AS "Rests com ≥2 contagens com controlado+peso",
    ROUND(
        (COUNT(*) FILTER (WHERE COALESCE(c.cnt, 0) >= 2)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥2 contagens)"
FROM qualified_base_count qb
LEFT JOIN contagens_controlled_weight_per_restaurant c ON qb.id = c.restaurant_id;


/* ============================================================================
   Metric V4 – per-restaurant (for consolidation)
   ==========================================================================*/

WITH clean_base AS (
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
      AND r.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
),

qualified_base_count AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.count_products = TRUE
),

inventories_with_controlled_weight AS (
    SELECT i.restaurant_id, i.id AS inventory_id
    FROM qualified_base_count qb
    JOIN inventory i
      ON i.restaurant_id = qb.id
      AND i.completed_at IS NOT NULL
      AND i.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN inventory_count ic ON ic.inventory_id = i.id
    JOIN controlled_products cp ON cp.restaurant_id = i.restaurant_id AND cp.product_id = ic.product_id
    JOIN products p ON p.id = cp.product_id AND COALESCE(p.weight, 0) > 0
    GROUP BY i.restaurant_id, i.id
),

contagens_controlled_weight_per_restaurant AS (
    SELECT restaurant_id, COUNT(DISTINCT inventory_id) AS cnt
    FROM inventories_with_controlled_weight
    GROUP BY restaurant_id
)

SELECT
    qb.id AS restaurant_id,
    COALESCE(c.cnt, 0) AS contagens_controlled_weight_cnt,
    CASE WHEN COALESCE(c.cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_v4_2_contagens_controlled_weight
FROM qualified_base_count qb
LEFT JOIN contagens_controlled_weight_per_restaurant c ON qb.id = c.restaurant_id;
