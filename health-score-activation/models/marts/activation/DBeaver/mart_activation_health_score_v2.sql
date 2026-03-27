-- Activation Health Score – Mart V2 (lifetime / no time window)
--
-- For top-tier clients: hygiene + count_products AND controlled_products enabled.
-- All activity metrics use full history (no 30-day signup cohort, no rolling 30-day filters).
-- Use to see which Setup / Effort / Value steps restaurants have ever reached.
--
-- Points, thresholds, and bucket labels match mart_activation_health_score.sql;
-- interpretation differs: scores reflect lifetime cumulative behavior, not activation-phase windows.
--
-- Performance: clean_base is MATERIALIZED; effort tags = one GROUP BY per source.
-- Weighted V1–V3: LATERAL + MATERIALIZED ti_weighted = tag_infos ∩ weighted restaurant_products
-- (single joined slice, then aggregates—avoids materializing all tag rows then hashing again to rp).
-- access_history: expect Seq Scan + hash to clean_base until a btree exists on restaurant_id (see below).
--
-- Suggested index (run on prod only after review): supports login aggregation by cohort.
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_access_history_restaurant_id
--     ON access_history (restaurant_id);
-- If you must join on (restaurant_id::uuid), an expression index can help, e.g.:
--   CREATE INDEX CONCURRENTLY ... ON access_history ((restaurant_id::uuid));

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
),

clean_base AS MATERIALIZED (
    SELECT br.restaurant_id AS id
    FROM base_restaurants br
    JOIN enable_feature ef ON ef.restaurant_id = br.restaurant_id
    WHERE ef.count_products = TRUE
      AND ef.controlled_products = TRUE
),

-- -------- Setup bucket (S1, S2, S3) --------
logins_by_role AS (
    SELECT
        cb.id AS restaurant_id,
        MAX(CASE WHEN a.role = 'restaurant_admin'    THEN 1 ELSE 0 END) AS has_gestor_login,
        MAX(CASE WHEN a.role = 'restaurant_employee' THEN 1 ELSE 0 END) AS has_colab_login
    FROM clean_base cb
    JOIN access_history ah
      ON ah.restaurant_id IS NOT NULL
     AND ah.restaurant_id ~ '^[0-9a-fA-F-]{36}$'
     AND (ah.restaurant_id::uuid) = cb.id
    JOIN authentications a ON a.login = ah.login
    GROUP BY cb.id
),
s1 AS (
    SELECT
        cb.id AS restaurant_id,
        CASE WHEN COALESCE(l.has_gestor_login, 0) = 1 AND COALESCE(l.has_colab_login, 0) = 1 THEN 1 ELSE 0 END AS hit_s1_logins
    FROM clean_base cb
    LEFT JOIN logins_by_role l ON cb.id = l.restaurant_id
),

lists_with_controlled AS (
    SELECT DISTINCT il.restaurant_id, il.id AS inventory_list_id
    FROM clean_base cb
    JOIN inventory_list il ON il.restaurant_id = cb.id
    JOIN inventory_list_products ilp ON il.id = ilp.inventory_list_id
    JOIN controlled_products cp ON cp.product_id = ilp.product_id
),
agg_s2 AS (
    SELECT restaurant_id, COUNT(DISTINCT inventory_list_id) AS lists_with_controlled_cnt
    FROM lists_with_controlled
    GROUP BY restaurant_id
),
s2 AS (
    SELECT
        cb.id AS restaurant_id,
        CASE WHEN COALESCE(a.lists_with_controlled_cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_s2_lists_with_controlled
    FROM clean_base cb
    LEFT JOIN agg_s2 a ON cb.id = a.restaurant_id
),

controlled_with_weight AS (
    SELECT cp.restaurant_id, COUNT(DISTINCT cp.id) AS controlled_weighted_cnt
    FROM clean_base cb
    JOIN controlled_products cp ON cp.restaurant_id = cb.id
    LEFT JOIN products p ON cp.product_id = p.id
    WHERE COALESCE(p.weight, 0) > 0
    GROUP BY cp.restaurant_id
),
s3 AS (
    SELECT
        cb.id AS restaurant_id,
        CASE WHEN COALESCE(cw.controlled_weighted_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_s3_controlled_with_weight
    FROM clean_base cb
    LEFT JOIN controlled_with_weight cw ON cb.id = cw.restaurant_id
),

-- -------- Effort E1–E3: one pass per tag source --------
tag_effort_production AS (
    SELECT
        ti.restaurant_id,
        SUM(COALESCE(ti.tags_count, 1)) AS sum_prints,
        SUM(
            CASE WHEN ti.controlled_product
                THEN COALESCE(ti.tags_count, 1)
                ELSE 0
            END
        ) AS sum_controlled_prints,
        SUM(COALESCE(ti.tags_count_removed, 0)) AS sum_baixas
    FROM tag_infos ti
    WHERE ti.restaurant_id IN (SELECT id FROM clean_base)
    GROUP BY ti.restaurant_id
),
tag_effort_receivings AS (
    SELECT
        tr.restaurant_id,
        SUM(COALESCE(tr.tags_count, 1)) AS sum_prints,
        SUM(
            CASE WHEN tr.controlled_product
                THEN COALESCE(tr.tags_count, 1)
                ELSE 0
            END
        ) AS sum_controlled_prints,
        SUM(COALESCE(tr.tags_count_removed, 0)) AS sum_baixas
    FROM tag_infos_receivings tr
    WHERE tr.restaurant_id IN (SELECT id FROM clean_base)
    GROUP BY tr.restaurant_id
),
effort_from_tags AS (
    SELECT
        cb.id AS restaurant_id,
        CASE
            WHEN COALESCE(tep.sum_prints, 0) + COALESCE(ter.sum_prints, 0) >= 50 THEN 1
            ELSE 0
        END AS hit_e1_50_prints,
        CASE
            WHEN COALESCE(tep.sum_controlled_prints, 0) + COALESCE(ter.sum_controlled_prints, 0) >= 30 THEN 1
            ELSE 0
        END AS hit_e2_30_controlled_prints,
        CASE
            WHEN COALESCE(tep.sum_baixas, 0) + COALESCE(ter.sum_baixas, 0) >= 10 THEN 1
            ELSE 0
        END AS hit_e3_10_baixas
    FROM clean_base cb
    LEFT JOIN tag_effort_production tep ON cb.id = tep.restaurant_id
    LEFT JOIN tag_effort_receivings ter ON cb.id = ter.restaurant_id
),

contagens_all_time AS (
    SELECT cb.id AS restaurant_id, COUNT(*) AS contagens_cnt
    FROM clean_base cb
    JOIN inventory i ON i.restaurant_id = cb.id AND i.completed_at IS NOT NULL
    GROUP BY cb.id
),
e4 AS (
    SELECT
        cb.id AS restaurant_id,
        CASE WHEN COALESCE(c.contagens_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_e4_5_contagens
    FROM clean_base cb
    LEFT JOIN contagens_all_time c ON cb.id = c.restaurant_id
),

-- -------- Value V1–V3: lateral; MATERIALIZED ti_weighted = tag rows ∩ weighted rp (one join phase, then SUM) --------
tag_value_weighted_production AS (
    SELECT
        cb.id AS restaurant_id,
        sub.v1_prints,
        sub.v2_prints,
        sub.v3_baixas
    FROM clean_base cb
    LEFT JOIN LATERAL (
        WITH ti_weighted AS MATERIALIZED (
            SELECT
                ti.tags_count,
                ti.controlled_product,
                ti.tags_count_removed
            FROM tag_infos ti
            JOIN restaurant_products rp
              ON rp.product_id = ti.product_id
             AND rp.restaurant_id = cb.id
            JOIN products p
              ON p.id = rp.product_id
             AND COALESCE(p.weight, 0) > 0
            WHERE ti.restaurant_id = cb.id
        )
        SELECT
            SUM(COALESCE(ti.tags_count, 1)) AS v1_prints,
            SUM(
                CASE WHEN ti.controlled_product
                    THEN COALESCE(ti.tags_count, 1)
                    ELSE 0
                END
            ) AS v2_prints,
            SUM(
                CASE WHEN ti.controlled_product
                    THEN COALESCE(ti.tags_count_removed, 0)
                    ELSE 0
                END
            ) AS v3_baixas
        FROM ti_weighted ti
    ) sub ON TRUE
),
tag_value_weighted_receivings AS (
    SELECT
        cb.id AS restaurant_id,
        sub.v1_prints,
        sub.v2_prints,
        sub.v3_baixas
    FROM clean_base cb
    LEFT JOIN LATERAL (
        WITH tr_weighted AS MATERIALIZED (
            SELECT
                tr.tags_count,
                tr.controlled_product,
                tr.tags_count_removed
            FROM tag_infos_receivings tr
            JOIN restaurant_products rp
              ON rp.product_id = tr.product_id
             AND rp.restaurant_id = cb.id
            JOIN products p
              ON p.id = rp.product_id
             AND COALESCE(p.weight, 0) > 0
            WHERE tr.restaurant_id = cb.id
        )
        SELECT
            SUM(COALESCE(tr.tags_count, 1)) AS v1_prints,
            SUM(
                CASE WHEN tr.controlled_product
                    THEN COALESCE(tr.tags_count, 1)
                    ELSE 0
                END
            ) AS v2_prints,
            SUM(
                CASE WHEN tr.controlled_product
                    THEN COALESCE(tr.tags_count_removed, 0)
                    ELSE 0
                END
            ) AS v3_baixas
        FROM tr_weighted tr
    ) sub ON TRUE
),

inventories_with_controlled_weight AS (
    SELECT i.restaurant_id, i.id AS inventory_id
    FROM clean_base cb
    JOIN inventory i ON i.restaurant_id = cb.id AND i.completed_at IS NOT NULL
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

value_from_tags AS (
    SELECT
        cb.id AS restaurant_id,
        CASE
            WHEN COALESCE(twp.v1_prints, 0) + COALESCE(twr.v1_prints, 0) >= 20 THEN 1
            ELSE 0
        END AS hit_v1_20_prints_weight,
        CASE
            WHEN COALESCE(twp.v2_prints, 0) + COALESCE(twr.v2_prints, 0) >= 30 THEN 1
            ELSE 0
        END AS hit_v2_30_controlled_weight,
        CASE
            WHEN COALESCE(twp.v3_baixas, 0) + COALESCE(twr.v3_baixas, 0) >= 5 THEN 1
            ELSE 0
        END AS hit_v3_5_baixas_controlled_weight,
        CASE WHEN COALESCE(v4.cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_v4_2_contagens_controlled_weight,
        CASE
            WHEN COALESCE(twp.v2_prints, 0) + COALESCE(twr.v2_prints, 0) >= 30
              OR COALESCE(twp.v3_baixas, 0) + COALESCE(twr.v3_baixas, 0) >= 5
              OR COALESCE(v4.cnt, 0) >= 2
            THEN 1
            ELSE 0
        END AS has_weighted_controlled_core_action
    FROM clean_base cb
    LEFT JOIN tag_value_weighted_production twp ON cb.id = twp.restaurant_id
    LEFT JOIN tag_value_weighted_receivings twr ON cb.id = twr.restaurant_id
    LEFT JOIN v4_per_restaurant v4 ON cb.id = v4.restaurant_id
),

-- -------- Points and bucket --------
per_restaurant_scores AS (
    SELECT
        cb.id AS restaurant_id,
        COALESCE(s1.hit_s1_logins, 0) * 2 AS pts_s1_logins,
        COALESCE(s2.hit_s2_lists_with_controlled, 0) * 3 AS pts_s2_lists_with_controlled,
        COALESCE(s3.hit_s3_controlled_with_weight, 0) * 5 AS pts_s3_controlled_with_weight,
        COALESCE(et.hit_e1_50_prints, 0) * 3 AS pts_e1_50_prints,
        COALESCE(et.hit_e2_30_controlled_prints, 0) * 7 AS pts_e2_30_controlled_prints,
        COALESCE(et.hit_e3_10_baixas, 0) * 15 AS pts_e3_10_baixas,
        COALESCE(e4.hit_e4_5_contagens, 0) * 5 AS pts_e4_5_contagens,
        COALESCE(v.hit_v1_20_prints_weight, 0) * 15 AS pts_v1_20_prints_weight,
        COALESCE(v.hit_v2_30_controlled_weight, 0) * 10 AS pts_v2_30_controlled_weight,
        COALESCE(v.hit_v3_5_baixas_controlled_weight, 0) * 25 AS pts_v3_5_baixas_controlled_weight,
        COALESCE(v.hit_v4_2_contagens_controlled_weight, 0) * 10 AS pts_v4_2_contagens_controlled_weight,
        (
            COALESCE(s1.hit_s1_logins, 0) * 2 +
            COALESCE(s2.hit_s2_lists_with_controlled, 0) * 3 +
            COALESCE(s3.hit_s3_controlled_with_weight, 0) * 5 +
            COALESCE(et.hit_e1_50_prints, 0) * 3 +
            COALESCE(et.hit_e2_30_controlled_prints, 0) * 7 +
            COALESCE(et.hit_e3_10_baixas, 0) * 15 +
            COALESCE(e4.hit_e4_5_contagens, 0) * 5 +
            COALESCE(v.hit_v1_20_prints_weight, 0) * 15 +
            COALESCE(v.hit_v2_30_controlled_weight, 0) * 10 +
            COALESCE(v.hit_v3_5_baixas_controlled_weight, 0) * 25 +
            COALESCE(v.hit_v4_2_contagens_controlled_weight, 0) * 10
        ) AS total_score,
        COALESCE(v.has_weighted_controlled_core_action, 0) AS has_weighted_controlled_core_action
    FROM clean_base cb
    LEFT JOIN s1 ON cb.id = s1.restaurant_id
    LEFT JOIN s2 ON cb.id = s2.restaurant_id
    LEFT JOIN s3 ON cb.id = s3.restaurant_id
    LEFT JOIN effort_from_tags et ON cb.id = et.restaurant_id
    LEFT JOIN e4 ON cb.id = e4.restaurant_id
    LEFT JOIN value_from_tags v ON cb.id = v.restaurant_id
)

SELECT
    prs.restaurant_id,
    prs.pts_s1_logins,
    prs.pts_s2_lists_with_controlled,
    prs.pts_s3_controlled_with_weight,
    prs.pts_e1_50_prints,
    prs.pts_e2_30_controlled_prints,
    prs.pts_e3_10_baixas,
    prs.pts_e4_5_contagens,
    prs.pts_v1_20_prints_weight,
    prs.pts_v2_30_controlled_weight,
    prs.pts_v3_5_baixas_controlled_weight,
    prs.pts_v4_2_contagens_controlled_weight,
    prs.total_score,
    prs.has_weighted_controlled_core_action,
    CASE
        WHEN prs.total_score >= 80 AND prs.has_weighted_controlled_core_action = 1 THEN 'green_activated'
        WHEN prs.total_score >= 80 AND prs.has_weighted_controlled_core_action = 0 THEN 'orange_false_positive'
        WHEN prs.total_score BETWEEN 40 AND 79 THEN 'yellow_at_risk'
        ELSE 'red_failure'
    END AS activation_bucket
FROM per_restaurant_scores prs;
