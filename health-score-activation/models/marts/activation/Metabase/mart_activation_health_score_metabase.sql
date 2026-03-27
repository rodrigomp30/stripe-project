-- =============================================================================
-- Activation Health Score — Metabase · summary (list / dashboard)
-- =============================================================================
-- Same scoring logic as mart_activation_health_score.sql — keep in sync on changes.
--
-- Cohort: `base_restaurants` includes hygiene filters and `inserted_at` in the last 30 days (TTVW).
-- Logins / prints / baixas / contagens use a rolling **last 30 days** window on activity.
--
-- Drill-down: mart_activation_health_score_metabase_metrics.sql — field filter `nome_do_restaurante`.
--
-- Metabase tips:
-- - Column order: Trading name → Restaurant ID → Dias desde cadastro → Bucket label → Bucket flag (1–4) → Total score → Key, Lock, Ativado.
-- - Bucket flag: 1 = Green, 2 = Orange, 3 = Yellow, 4 = Red (same order as bucket labels).
-- - Granular Setup / Effort / Value flags live in the metrics companion query (not here).
-- - Total score is numeric (0–100); Key / Lock / Ativado use ✅ / ❌.
--
-- S1 split: this file awards Setup S1 as 1 pt + 1 pt (gestor · colaborador). The
-- canonical mart (mart_activation_health_score.sql) uses a single 2-pt block
-- when both roles logged in — totals match when both or neither qualify; if only
-- one role logged in, Metabase total can be +1 vs the canonical mart.
-- =============================================================================

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

logins_by_role AS (
    SELECT
        (ah.restaurant_id::uuid) AS restaurant_id,
        MAX(CASE WHEN a.role = 'restaurant_admin'    THEN 1 ELSE 0 END) AS has_gestor_login,
        MAX(CASE WHEN a.role = 'restaurant_employee' THEN 1 ELSE 0 END) AS has_colab_login
    FROM access_history ah
    JOIN authentications a ON a.login = ah.login
    WHERE ah.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
      AND ah.restaurant_id IS NOT NULL
      AND ah.restaurant_id ~ '^[0-9a-fA-F-]{36}$'
    GROUP BY ah.restaurant_id
),
s1 AS (
    SELECT
        cb.id AS restaurant_id,
        COALESCE(l.has_gestor_login, 0) AS has_gestor_login,
        COALESCE(l.has_colab_login, 0) AS has_colab_login
    FROM clean_base cb
    LEFT JOIN logins_by_role l ON cb.id = l.restaurant_id
),

qualified_base_count AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.count_products = TRUE
),
lists_with_controlled AS (
    SELECT DISTINCT il.restaurant_id, il.id AS inventory_list_id
    FROM inventory_list il
    JOIN inventory_list_products ilp ON il.id = ilp.inventory_list_id
    JOIN controlled_products cp ON cp.product_id = ilp.product_id
    WHERE il.restaurant_id IN (SELECT id FROM qualified_base_count)
),
agg_s2 AS (
    SELECT restaurant_id, COUNT(DISTINCT inventory_list_id) AS lists_with_controlled_cnt
    FROM lists_with_controlled
    GROUP BY restaurant_id
),
s2 AS (
    SELECT
        qb.id AS restaurant_id,
        CASE WHEN COALESCE(a.lists_with_controlled_cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_s2_lists_with_controlled
    FROM qualified_base_count qb
    LEFT JOIN agg_s2 a ON qb.id = a.restaurant_id
),

qualified_base_controlled AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.controlled_products = TRUE
),
controlled_with_weight AS (
    SELECT cp.restaurant_id, COUNT(DISTINCT cp.id) AS controlled_weighted_cnt
    FROM controlled_products cp
    LEFT JOIN products p ON cp.product_id = p.id
    WHERE cp.restaurant_id IN (SELECT id FROM qualified_base_controlled)
      AND COALESCE(p.weight, 0) > 0
    GROUP BY cp.restaurant_id
),
s3 AS (
    SELECT
        qb.id AS restaurant_id,
        CASE WHEN COALESCE(cw.controlled_weighted_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_s3_controlled_with_weight
    FROM qualified_base_controlled qb
    LEFT JOIN controlled_with_weight cw ON qb.id = cw.restaurant_id
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
),

per_restaurant_scores AS (
    SELECT
        b.restaurant_id,
        COALESCE(s1.has_gestor_login, 0) AS pts_s1_gestor,
        COALESCE(s1.has_colab_login, 0) AS pts_s1_colaborador,
        COALESCE(s2.hit_s2_lists_with_controlled, 0) * 3 AS pts_s2_lists_with_controlled,
        COALESCE(s3.hit_s3_controlled_with_weight, 0) * 5 AS pts_s3_controlled_with_weight,
        COALESCE(e1.hit_e1_50_prints, 0) * 3 AS pts_e1_50_prints,
        COALESCE(e2.hit_e2_30_controlled_prints, 0) * 7 AS pts_e2_30_controlled_prints,
        COALESCE(e3.hit_e3_10_baixas, 0) * 15 AS pts_e3_10_baixas,
        COALESCE(e4.hit_e4_5_contagens, 0) * 5 AS pts_e4_5_contagens,
        COALESCE(v.hit_v1_20_prints_weight, 0) * 15 AS pts_v1_20_prints_weight,
        COALESCE(v.hit_v2_30_controlled_weight, 0) * 10 AS pts_v2_30_controlled_weight,
        COALESCE(v.hit_v3_5_baixas_controlled_weight, 0) * 25 AS pts_v3_5_baixas_controlled_weight,
        COALESCE(v.hit_v4_2_contagens_controlled_weight, 0) * 10 AS pts_v4_2_contagens_controlled_weight,
        (
            COALESCE(s1.has_gestor_login, 0) +
            COALESCE(s1.has_colab_login, 0) +
            COALESCE(s2.hit_s2_lists_with_controlled, 0) * 3 +
            COALESCE(s3.hit_s3_controlled_with_weight, 0) * 5 +
            COALESCE(e1.hit_e1_50_prints, 0) * 3 +
            COALESCE(e2.hit_e2_30_controlled_prints, 0) * 7 +
            COALESCE(e3.hit_e3_10_baixas, 0) * 15 +
            COALESCE(e4.hit_e4_5_contagens, 0) * 5 +
            COALESCE(v.hit_v1_20_prints_weight, 0) * 15 +
            COALESCE(v.hit_v2_30_controlled_weight, 0) * 10 +
            COALESCE(v.hit_v3_5_baixas_controlled_weight, 0) * 25 +
            COALESCE(v.hit_v4_2_contagens_controlled_weight, 0) * 10
        ) AS total_score,
        COALESCE(v.has_weighted_controlled_core_action, 0) AS has_weighted_controlled_core_action
    FROM base_restaurants b
    LEFT JOIN s1 ON b.restaurant_id = s1.restaurant_id
    LEFT JOIN s2 ON b.restaurant_id = s2.restaurant_id
    LEFT JOIN s3 ON b.restaurant_id = s3.restaurant_id
    LEFT JOIN e1 ON b.restaurant_id = e1.restaurant_id
    LEFT JOIN e2 ON b.restaurant_id = e2.restaurant_id
    LEFT JOIN e3 ON b.restaurant_id = e3.restaurant_id
    LEFT JOIN e4 ON b.restaurant_id = e4.restaurant_id
    LEFT JOIN value_metrics v ON b.restaurant_id = v.restaurant_id
),

final AS (
    SELECT
        prs.*,
        CASE
            WHEN prs.total_score >= 80 AND prs.has_weighted_controlled_core_action = 1 THEN 'green_activated'
            WHEN prs.total_score >= 80 AND prs.has_weighted_controlled_core_action = 0 THEN 'orange_false_positive'
            WHEN prs.total_score BETWEEN 40 AND 79 THEN 'yellow_at_risk'
            ELSE 'red_failure'
        END AS activation_bucket
    FROM per_restaurant_scores prs
)

SELECT
    r.trading_name AS "Trading name",
    f.restaurant_id AS "Restaurant ID",
    (CURRENT_DATE - (r.inserted_at)::date) AS "Dias desde cadastro",
    CASE f.activation_bucket
        WHEN 'green_activated' THEN '✅ Green · Activated (>80 + Value Act.)'
        WHEN 'orange_false_positive' THEN '⚠️ Orange · Alto score, Key missing'
        WHEN 'yellow_at_risk' THEN '🟡 Yellow · Em risco (40–79)'
        ELSE '🔴 Red · Baixa ativação (<40)'
    END AS "Bucket label",
    CASE f.activation_bucket
        WHEN 'green_activated' THEN 1
        WHEN 'orange_false_positive' THEN 2
        WHEN 'yellow_at_risk' THEN 3
        ELSE 4
    END AS "Bucket flag",
    f.total_score AS "Total score",

    CASE WHEN f.has_weighted_controlled_core_action = 1 THEN '✅' ELSE '❌' END AS "Completou ≥1 ação de Geração de Valor (Key)",

    CASE WHEN f.total_score >= 80 THEN '✅' ELSE '❌' END AS "Lock",
    CASE WHEN f.total_score >= 80 AND f.has_weighted_controlled_core_action = 1 THEN '✅' ELSE '❌' END AS "Ativado (Lock + Key)"

FROM final f
JOIN restaurants r ON r.id = f.restaurant_id;
