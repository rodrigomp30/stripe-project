-- Activation – Effort & Commitment Bucket Metrics (Viability Queries)
-- 
-- Run with or without EXPLAIN in DBeaver to validate feasibility of Effort
-- milestones. Keep v1 and v2 versions to track how the queries evolved.

/* ============================================================================
   Metric E1 v1 – 50 prints (any product)
   ---------------------------------------------------------------------------
   Original version: uses a time_window CTE and aggregates globally.
   ==========================================================================*/

EXPLAIN
WITH time_window AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_date
),

clean_base AS (
    SELECT r.id
    FROM restaurants r
    CROSS JOIN time_window tw
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
      AND r.inserted_at >= tw.start_date
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.production_tags = TRUE
),

prints_last_30d AS (
    SELECT
        t.restaurant_id,
        COUNT(*) AS prints_cnt
    FROM (
        SELECT restaurant_id, inserted_at
        FROM tags
        UNION ALL
        SELECT restaurant_id, inserted_at
        FROM tags_receivings
    ) t
    CROSS JOIN time_window tw
    WHERE t.inserted_at >= tw.start_date
      AND t.restaurant_id IN (SELECT id FROM qualified_base)
    GROUP BY t.restaurant_id
)

SELECT
    COUNT(qb.id) AS "Base (Impressão Habilitada)",
    COUNT(p.restaurant_id) AS "Rests com ≥1 impressão",
    COUNT(*) FILTER (
        WHERE COALESCE(p.prints_cnt, 0) >= 50
    ) AS "Rests com ≥50 impressões",
    ROUND(
        (COUNT(*) FILTER (WHERE COALESCE(p.prints_cnt, 0) >= 50)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥50 impressões)"
FROM qualified_base qb
LEFT JOIN prints_last_30d p ON qb.id = p.restaurant_id;


/* ============================================================================
   Metric E1 v2 – 50 prints (any product, optimized + per-restaurant counts)
   ---------------------------------------------------------------------------
   Optimized version:
   - Drops time_window CTE to avoid optimization fence.
   - Pushes date filter directly into tags/tags_receivings.
   - Still returns global aggregates; you can also SELECT restaurant_id + prints_cnt
     from prints_last_30d if you need per-restaurant flags later.
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

prints_last_30d AS (
    SELECT
        t.restaurant_id,
        COUNT(*) AS prints_cnt
    FROM (
        SELECT restaurant_id, inserted_at
        FROM tags
        WHERE inserted_at >= (CURRENT_DATE - INTERVAL '30 days')

        UNION ALL

        SELECT restaurant_id, inserted_at
        FROM tags_receivings
        WHERE inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    ) t
    WHERE t.restaurant_id IN (SELECT id FROM qualified_base)
    GROUP BY t.restaurant_id
)

SELECT
    COUNT(qb.id) AS "Base (Impressão Habilitada)",
    COUNT(p.restaurant_id) AS "Rests com ≥1 impressão",
    COUNT(*) FILTER (
        WHERE COALESCE(p.prints_cnt, 0) >= 50
    ) AS "Rests com ≥50 impressões",
    ROUND(
        (COUNT(*) FILTER (WHERE COALESCE(p.prints_cnt, 0) >= 50)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥50 impressões)"
FROM qualified_base qb
LEFT JOIN prints_last_30d p ON qb.id = p.restaurant_id;


/* ============================================================================
   Metric E1 v3 – 50 prints (any product), using tag_infos + tags_count
   ---------------------------------------------------------------------------
   Do NOT use tags / tags_receivings: restaurant_id there is not reliable.
   Use tag_infos and tag_infos_receivings to filter by restaurant; use the
   tags_count field for the number of prints per row.
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

prints_last_30d AS (
    SELECT
        t.restaurant_id,
        SUM(t.tags_count) AS prints_cnt
    FROM (
        SELECT restaurant_id, inserted_at, COALESCE(tags_count, 1) AS tags_count
        FROM tag_infos
        WHERE inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
          AND restaurant_id IS NOT NULL

        UNION ALL

        SELECT restaurant_id, inserted_at, COALESCE(tags_count, 1) AS tags_count
        FROM tag_infos_receivings
        WHERE inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
          AND restaurant_id IS NOT NULL
    ) t
    WHERE t.restaurant_id IN (SELECT id FROM qualified_base)
    GROUP BY t.restaurant_id
)

SELECT
    COUNT(qb.id) AS "Base (Impressão Habilitada)",
    COUNT(p.restaurant_id) AS "Rests com ≥1 impressão",
    COUNT(*) FILTER (
        WHERE COALESCE(p.prints_cnt, 0) >= 50
    ) AS "Rests com ≥50 impressões",
    ROUND(
        (COUNT(*) FILTER (WHERE COALESCE(p.prints_cnt, 0) >= 50)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥50 impressões)"
FROM qualified_base qb
LEFT JOIN prints_last_30d p ON qb.id = p.restaurant_id;


/* ============================================================================
   Metric E1 v4 – 50 prints (tag_infos), cost-optimized (<500k target)
   ---------------------------------------------------------------------------
   Drive from qualified_base and join to tag_infos / tag_infos_receivings so
   the planner can use index on restaurant_id and only read rows for those
   restaurants (aim: 200k–300k cost).
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

prints_production AS (
    SELECT
        qb.id AS restaurant_id,
        SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti
      ON ti.restaurant_id = qb.id
      AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
),

prints_receivings AS (
    SELECT
        qb.id AS restaurant_id,
        SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr
      ON tr.restaurant_id = qb.id
      AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
)

SELECT
    COUNT(qb.id) AS "Base (Impressão Habilitada)",
    COUNT(*) FILTER (WHERE (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 1) AS "Rests com ≥1 impressão",
    COUNT(*) FILTER (
        WHERE (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 50
    ) AS "Rests com ≥50 impressões",
    ROUND(
        (COUNT(*) FILTER (WHERE (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 50)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥50 impressões)"
FROM qualified_base qb
LEFT JOIN prints_production pp ON qb.id = pp.restaurant_id
LEFT JOIN prints_receivings  pr ON qb.id = pr.restaurant_id;


/* ============================================================================
   Metric E1 v4 – per-restaurant (for consolidation)
   ---------------------------------------------------------------------------
   Same CTEs as E1 v4 above; returns one row per restaurant with
   restaurant_id, prints_cnt, hit_e1_50_prints (0/1).
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

prints_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti ON ti.restaurant_id = qb.id AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
),

prints_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr ON tr.restaurant_id = qb.id AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
)

SELECT
    qb.id AS restaurant_id,
    (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) AS prints_cnt,
    CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 50 THEN 1 ELSE 0 END AS hit_e1_50_prints
FROM qualified_base qb
LEFT JOIN prints_production pp ON qb.id = pp.restaurant_id
LEFT JOIN prints_receivings  pr ON qb.id = pr.restaurant_id;


/* ============================================================================
   Metric E2 – 30 impressões de produtos controlados (7 pts)
   ---------------------------------------------------------------------------
   Same as E1 v4 but only rows where controlled_product = TRUE.
   Drive from qualified_base to keep cost low.
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

controlled_prints_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti
      ON ti.restaurant_id = qb.id
      AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
      AND ti.controlled_product = TRUE
    GROUP BY qb.id
),

controlled_prints_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr
      ON tr.restaurant_id = qb.id
      AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
      AND tr.controlled_product = TRUE
    GROUP BY qb.id
)

SELECT
    COUNT(qb.id) AS "Base (Impressão Habilitada)",
    COUNT(*) FILTER (WHERE (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 1) AS "Rests com ≥1 impressão controlada",
    COUNT(*) FILTER (WHERE (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30) AS "Rests com ≥30 impressões controladas",
    ROUND(
        (COUNT(*) FILTER (WHERE (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥30 controladas)"
FROM qualified_base qb
LEFT JOIN controlled_prints_production pp ON qb.id = pp.restaurant_id
LEFT JOIN controlled_prints_receivings  pr ON qb.id = pr.restaurant_id;


/* ============================================================================
   Metric E2 – per-restaurant (for consolidation)
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

controlled_prints_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti ON ti.restaurant_id = qb.id AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND ti.controlled_product = TRUE
    GROUP BY qb.id
),

controlled_prints_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count, 1)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr ON tr.restaurant_id = qb.id AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tr.controlled_product = TRUE
    GROUP BY qb.id
)

SELECT
    qb.id AS restaurant_id,
    (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) AS controlled_prints_cnt,
    CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_e2_30_controlled_prints
FROM qualified_base qb
LEFT JOIN controlled_prints_production pp ON qb.id = pp.restaurant_id
LEFT JOIN controlled_prints_receivings  pr ON qb.id = pr.restaurant_id;


/* ============================================================================
   Metric E3 – 10 baixas realizadas (15 pts)
   ---------------------------------------------------------------------------
   Baixas = tags_count_removed in tag_infos + tag_infos_receivings.
   Drive from qualified_base (production_tags), same 30-day window.
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

baixas_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti
      ON ti.restaurant_id = qb.id
      AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
),

baixas_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr
      ON tr.restaurant_id = qb.id
      AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
)

SELECT
    COUNT(qb.id) AS "Base (Impressão Habilitada)",
    COUNT(*) FILTER (WHERE (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 1) AS "Rests com ≥1 baixa",
    COUNT(*) FILTER (WHERE (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 10) AS "Rests com ≥10 baixas",
    ROUND(
        (COUNT(*) FILTER (WHERE (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 10)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥10 baixas)"
FROM qualified_base qb
LEFT JOIN baixas_production bp ON qb.id = bp.restaurant_id
LEFT JOIN baixas_receivings  br ON qb.id = br.restaurant_id;


/* ============================================================================
   Metric E3 – per-restaurant (for consolidation)
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

baixas_production AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(ti.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos ti ON ti.restaurant_id = qb.id AND ti.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
),

baixas_receivings AS (
    SELECT qb.id AS restaurant_id, SUM(COALESCE(tr.tags_count_removed, 0)) AS cnt
    FROM qualified_base qb
    JOIN tag_infos_receivings tr ON tr.restaurant_id = qb.id AND tr.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
)

SELECT
    qb.id AS restaurant_id,
    (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) AS baixas_cnt,
    CASE WHEN (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 10 THEN 1 ELSE 0 END AS hit_e3_10_baixas
FROM qualified_base qb
LEFT JOIN baixas_production bp ON qb.id = bp.restaurant_id
LEFT JOIN baixas_receivings  br ON qb.id = br.restaurant_id;


/* ============================================================================
   Metric E4 – 5 contagens (5 pts)
   ---------------------------------------------------------------------------
   One "contagem" = one inventory with completed_at IS NOT NULL.
   Base: qualified_base_count (count_products = TRUE). Drive from base, join
   inventory on restaurant_id, filter completed_at in last 30 days.
   Ref: docs/references/counting_feature_metrics_reference.sql (Metric 3/4).
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

contagens_last_30d AS (
    SELECT qb.id AS restaurant_id, COUNT(*) AS contagens_cnt
    FROM qualified_base_count qb
    JOIN inventory i
      ON i.restaurant_id = qb.id
      AND i.completed_at IS NOT NULL
      AND i.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
)

SELECT
    COUNT(qb.id) AS "Base (Contagem Habilitada)",
    COUNT(*) FILTER (WHERE COALESCE(c.contagens_cnt, 0) >= 1) AS "Rests com ≥1 contagem",
    COUNT(*) FILTER (WHERE COALESCE(c.contagens_cnt, 0) >= 5) AS "Rests com ≥5 contagens",
    ROUND(
        (COUNT(*) FILTER (WHERE COALESCE(c.contagens_cnt, 0) >= 5)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥5 contagens)"
FROM qualified_base_count qb
LEFT JOIN contagens_last_30d c ON qb.id = c.restaurant_id;


/* ============================================================================
   Metric E4 – per-restaurant (for consolidation)
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

contagens_last_30d AS (
    SELECT qb.id AS restaurant_id, COUNT(*) AS contagens_cnt
    FROM qualified_base_count qb
    JOIN inventory i
      ON i.restaurant_id = qb.id
      AND i.completed_at IS NOT NULL
      AND i.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
)

SELECT
    qb.id AS restaurant_id,
    COALESCE(c.contagens_cnt, 0) AS contagens_cnt,
    CASE WHEN COALESCE(c.contagens_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_e4_5_contagens
FROM qualified_base_count qb
LEFT JOIN contagens_last_30d c ON qb.id = c.restaurant_id;
