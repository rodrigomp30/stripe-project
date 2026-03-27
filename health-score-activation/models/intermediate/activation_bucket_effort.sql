-- Activation Health Score – Effort Bucket (Intermediate Model)
--
-- One row per restaurant that has at least one Effort metric (E1–E4).
-- Does NOT define the cohort; consolidation defines base_restaurants and LEFT JOINs this.
-- Outputs: restaurant_id, E1–E4 hit flags (and optional raw counts).
-- Logic from viability_tests/activation_effort_metrics.sql (per-restaurant blocks).

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

-- E1: 50 impressões
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
        (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) AS prints_cnt,
        CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 50 THEN 1 ELSE 0 END AS hit_e1_50_prints
    FROM qualified_base qb
    LEFT JOIN prints_production pp ON qb.id = pp.restaurant_id
    LEFT JOIN prints_receivings pr ON qb.id = pr.restaurant_id
),

-- E2: 30 impressões controladas
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
        (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) AS controlled_prints_cnt,
        CASE WHEN (COALESCE(pp.cnt, 0) + COALESCE(pr.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_e2_30_controlled_prints
    FROM qualified_base qb
    LEFT JOIN controlled_prints_production pp ON qb.id = pp.restaurant_id
    LEFT JOIN controlled_prints_receivings pr ON qb.id = pr.restaurant_id
),

-- E3: 10 baixas
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
        (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) AS baixas_cnt,
        CASE WHEN (COALESCE(bp.cnt, 0) + COALESCE(br.cnt, 0)) >= 10 THEN 1 ELSE 0 END AS hit_e3_10_baixas
    FROM qualified_base qb
    LEFT JOIN baixas_production bp ON qb.id = bp.restaurant_id
    LEFT JOIN baixas_receivings br ON qb.id = br.restaurant_id
),

-- E4: 5 contagens (base: count_products)
qualified_base_count AS (
    SELECT h.id
    FROM hygiene_restaurant_ids h
    JOIN enable_feature ef ON ef.restaurant_id = h.id
    WHERE ef.count_products = TRUE
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
        COALESCE(c.contagens_cnt, 0) AS contagens_cnt,
        CASE WHEN COALESCE(c.contagens_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_e4_5_contagens
    FROM qualified_base_count qb
    LEFT JOIN contagens_last_30d c ON qb.id = c.restaurant_id
),

all_restaurant_ids AS (
    SELECT restaurant_id FROM e1
    UNION
    SELECT restaurant_id FROM e2
    UNION
    SELECT restaurant_id FROM e3
    UNION
    SELECT restaurant_id FROM e4
)

SELECT
    a.restaurant_id,
    COALESCE(e1.prints_cnt, 0) AS prints_cnt,
    COALESCE(e1.hit_e1_50_prints, 0) AS hit_e1_50_prints,
    COALESCE(e2.controlled_prints_cnt, 0) AS controlled_prints_cnt,
    COALESCE(e2.hit_e2_30_controlled_prints, 0) AS hit_e2_30_controlled_prints,
    COALESCE(e3.baixas_cnt, 0) AS baixas_cnt,
    COALESCE(e3.hit_e3_10_baixas, 0) AS hit_e3_10_baixas,
    COALESCE(e4.contagens_cnt, 0) AS contagens_cnt,
    COALESCE(e4.hit_e4_5_contagens, 0) AS hit_e4_5_contagens
FROM all_restaurant_ids a
LEFT JOIN e1 ON a.restaurant_id = e1.restaurant_id
LEFT JOIN e2 ON a.restaurant_id = e2.restaurant_id
LEFT JOIN e3 ON a.restaurant_id = e3.restaurant_id
LEFT JOIN e4 ON a.restaurant_id = e4.restaurant_id;
