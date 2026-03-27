-- =============================================================================
-- Test 2: Effort + Consolidation
-- Same cohort in both steps. Compare pts_e1, pts_e2, pts_e3, pts_e4; they must match.
-- Step 2: run models/marts/activation/mart_activation_health_score.sql separately.
-- Run Step 1, then Step 2, then Step 3 to get mismatches (0 rows = pass).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Step 1: Effort points for cohort only (same cohort & column names as Step 2)
-- Output: one row per cohort restaurant, only Effort point columns.
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
),
e1 AS (
    SELECT
        qb.id AS restaurant_id,
        CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 50 THEN 1 ELSE 0 END AS hit_e1_50_prints
    FROM qualified_base qb
    LEFT JOIN prints_production pp ON qb.id = pp.restaurant_id
    LEFT JOIN prints_receivings pr ON qb.id = pr.restaurant_id
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
),
e2 AS (
    SELECT
        qb.id AS restaurant_id,
        CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_e2_30_controlled_prints
    FROM qualified_base qb
    LEFT JOIN controlled_prints_production pp ON qb.id = pp.restaurant_id
    LEFT JOIN controlled_prints_receivings pr ON qb.id = pr.restaurant_id
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
),
e3 AS (
    SELECT
        qb.id AS restaurant_id,
        CASE WHEN (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 10 THEN 1 ELSE 0 END AS hit_e3_10_baixas
    FROM qualified_base qb
    LEFT JOIN baixas_production bp ON qb.id = bp.restaurant_id
    LEFT JOIN baixas_receivings br ON qb.id = br.restaurant_id
),

contagens_last_30d AS (
    SELECT qb.id AS restaurant_id, COUNT(*) AS contagens_cnt
    FROM qualified_base_count qb
    JOIN inventory i ON i.restaurant_id = qb.id AND i.completed_at IS NOT NULL AND i.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qb.id
),
e4 AS (
    SELECT
        qb.id AS restaurant_id,
        CASE WHEN COALESCE(c.contagens_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_e4_5_contagens
    FROM qualified_base_count qb
    LEFT JOIN contagens_last_30d c ON qb.id = c.restaurant_id
)

SELECT
    b.restaurant_id,
    COALESCE(e1.hit_e1_50_prints, 0) * 3 AS pts_e1_50_prints,
    COALESCE(e2.hit_e2_30_controlled_prints, 0) * 7 AS pts_e2_30_controlled_prints,
    COALESCE(e3.hit_e3_10_baixas, 0) * 15 AS pts_e3_10_baixas,
    COALESCE(e4.hit_e4_5_contagens, 0) * 5 AS pts_e4_5_contagens
FROM base_restaurants b
LEFT JOIN e1 ON b.restaurant_id = e1.restaurant_id
LEFT JOIN e2 ON b.restaurant_id = e2.restaurant_id
LEFT JOIN e3 ON b.restaurant_id = e3.restaurant_id
LEFT JOIN e4 ON b.restaurant_id = e4.restaurant_id;


-- -----------------------------------------------------------------------------
-- Step 2: Full consolidation (all buckets)
-- Run in DBeaver: models/marts/activation/mart_activation_health_score.sql
-- Check: same cohort; Effort columns pts_e1_50_prints ... pts_e4_5_contagens; EXPLAIN cost < 500k.
-- -----------------------------------------------------------------------------
-- (Execute the mart file separately.)


-- -----------------------------------------------------------------------------
-- Step 3: Comparison — do Effort points match between Step 1 and Step 2?
-- Runs Step 1 and duplicate Effort logic; 0 rows = pass.
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
    ),
    e1 AS (
        SELECT qb.id AS restaurant_id,
               CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 50 THEN 1 ELSE 0 END AS hit_e1_50_prints
        FROM qualified_base qb
        LEFT JOIN prints_production pp ON qb.id = pp.restaurant_id
        LEFT JOIN prints_receivings pr ON qb.id = pr.restaurant_id
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
    ),
    e2 AS (
        SELECT qb.id AS restaurant_id,
               CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_e2_30_controlled_prints
        FROM qualified_base qb
        LEFT JOIN controlled_prints_production pp ON qb.id = pp.restaurant_id
        LEFT JOIN controlled_prints_receivings pr ON qb.id = pr.restaurant_id
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
    ),
    e3 AS (
        SELECT qb.id AS restaurant_id,
               CASE WHEN (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 10 THEN 1 ELSE 0 END AS hit_e3_10_baixas
        FROM qualified_base qb
        LEFT JOIN baixas_production bp ON qb.id = bp.restaurant_id
        LEFT JOIN baixas_receivings br ON qb.id = br.restaurant_id
    ),
    contagens_last_30d AS (
        SELECT qb.id AS restaurant_id, COUNT(*) AS contagens_cnt
        FROM qualified_base_count qb
        JOIN inventory i ON i.restaurant_id = qb.id AND i.completed_at IS NOT NULL AND i.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
        GROUP BY qb.id
    ),
    e4 AS (
        SELECT qb.id AS restaurant_id,
               CASE WHEN COALESCE(c.contagens_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_e4_5_contagens
        FROM qualified_base_count qb
        LEFT JOIN contagens_last_30d c ON qb.id = c.restaurant_id
    )
    SELECT
        b.restaurant_id,
        COALESCE(e1.hit_e1_50_prints, 0) * 3 AS pts_e1_50_prints,
        COALESCE(e2.hit_e2_30_controlled_prints, 0) * 7 AS pts_e2_30_controlled_prints,
        COALESCE(e3.hit_e3_10_baixas, 0) * 15 AS pts_e3_10_baixas,
        COALESCE(e4.hit_e4_5_contagens, 0) * 5 AS pts_e4_5_contagens
    FROM base_restaurants b
    LEFT JOIN e1 ON b.restaurant_id = e1.restaurant_id
    LEFT JOIN e2 ON b.restaurant_id = e2.restaurant_id
    LEFT JOIN e3 ON b.restaurant_id = e3.restaurant_id
    LEFT JOIN e4 ON b.restaurant_id = e4.restaurant_id
),

step2_effort_cols AS MATERIALIZED (
    -- Same Effort logic as Step 1 (and as consolidation)
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
    ),
    e1 AS (
        SELECT qb.id AS restaurant_id,
               CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 50 THEN 1 ELSE 0 END AS hit_e1_50_prints
        FROM qualified_base qb
        LEFT JOIN prints_production pp ON qb.id = pp.restaurant_id
        LEFT JOIN prints_receivings pr ON qb.id = pr.restaurant_id
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
    ),
    e2 AS (
        SELECT qb.id AS restaurant_id,
               CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_e2_30_controlled_prints
        FROM qualified_base qb
        LEFT JOIN controlled_prints_production pp ON qb.id = pp.restaurant_id
        LEFT JOIN controlled_prints_receivings pr ON qb.id = pr.restaurant_id
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
    ),
    e3 AS (
        SELECT qb.id AS restaurant_id,
               CASE WHEN (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 10 THEN 1 ELSE 0 END AS hit_e3_10_baixas
        FROM qualified_base qb
        LEFT JOIN baixas_production bp ON qb.id = bp.restaurant_id
        LEFT JOIN baixas_receivings br ON qb.id = br.restaurant_id
    ),
    contagens_last_30d AS (
        SELECT qb.id AS restaurant_id, COUNT(*) AS contagens_cnt
        FROM qualified_base_count qb
        JOIN inventory i ON i.restaurant_id = qb.id AND i.completed_at IS NOT NULL AND i.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
        GROUP BY qb.id
    ),
    e4 AS (
        SELECT qb.id AS restaurant_id,
               CASE WHEN COALESCE(c.contagens_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_e4_5_contagens
        FROM qualified_base_count qb
        LEFT JOIN contagens_last_30d c ON qb.id = c.restaurant_id
    )
    SELECT
        b.restaurant_id,
        COALESCE(e1.hit_e1_50_prints, 0) * 3 AS pts_e1_50_prints,
        COALESCE(e2.hit_e2_30_controlled_prints, 0) * 7 AS pts_e2_30_controlled_prints,
        COALESCE(e3.hit_e3_10_baixas, 0) * 15 AS pts_e3_10_baixas,
        COALESCE(e4.hit_e4_5_contagens, 0) * 5 AS pts_e4_5_contagens
    FROM base_restaurants b
    LEFT JOIN e1 ON b.restaurant_id = e1.restaurant_id
    LEFT JOIN e2 ON b.restaurant_id = e2.restaurant_id
    LEFT JOIN e3 ON b.restaurant_id = e3.restaurant_id
    LEFT JOIN e4 ON b.restaurant_id = e4.restaurant_id
)

SELECT
    'MISMATCH' AS status,
    a.restaurant_id,
    a.pts_e1_50_prints AS step1_e1,
    b.pts_e1_50_prints AS step2_e1,
    a.pts_e2_30_controlled_prints AS step1_e2,
    b.pts_e2_30_controlled_prints AS step2_e2,
    a.pts_e3_10_baixas AS step1_e3,
    b.pts_e3_10_baixas AS step2_e3,
    a.pts_e4_5_contagens AS step1_e4,
    b.pts_e4_5_contagens AS step2_e4
FROM step1 a
JOIN step2_effort_cols b ON a.restaurant_id = b.restaurant_id
WHERE a.pts_e1_50_prints IS DISTINCT FROM b.pts_e1_50_prints
   OR a.pts_e2_30_controlled_prints IS DISTINCT FROM b.pts_e2_30_controlled_prints
   OR a.pts_e3_10_baixas IS DISTINCT FROM b.pts_e3_10_baixas
   OR a.pts_e4_5_contagens IS DISTINCT FROM b.pts_e4_5_contagens;
-- 0 rows = Test 2 pass.
