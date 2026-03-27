-- =============================================================================
-- Activation Health Score — Metabase · metric flags (drill-down / detail)
-- =============================================================================
-- Pair with: mart_activation_health_score_metabase.sql (summary list).
-- Same scoring logic as mart_activation_health_score.sql — keep both Metabase files in sync.
--
-- Cohort: same as summary — `inserted_at` in the last 30 days on `restaurants` (plus hygiene + field filter below).
--
-- Metabase setup:
-- 1. Native question → paste this entire script.
-- 2. **Field filter** on `restaurants.trading_name` (not a plain Text variable). Metabase injects
--    SQL like `restaurants.trading_name = ...` — use full table name `restaurants` (no short alias)
--    in the clause below, same pattern as your other questions (`nome_do_restaurante`):
--        AND ( 1=0 [[ OR (1=1 AND {{nome_do_restaurante}}) ]] )
--    When the optional `[[ OR ... ]]` is omitted, `1=0` matches no rows — connect the filter on the dashboard.
-- 3. Dashboard: link the field filter from the summary card.
--
-- Returns matching row(s): trading name + ID + Setup / Effort / Value ✅❌ columns.
--
-- Style: base tables use full names (restaurants, tag_infos, …) with no short
-- aliases. CTEs keep their names (clean_base, qualified_base, s1, value_metrics, …).
-- =============================================================================

WITH base_restaurants AS (
    SELECT restaurants.id AS restaurant_id
    FROM restaurants
    WHERE restaurants.deleted_at IS NULL
      AND restaurants.is_blocked IS FALSE
      AND (restaurants.email IS NULL OR restaurants.email NOT ILIKE '%suflex%')
      AND (restaurants.trading_name IS NULL OR restaurants.trading_name NOT ILIKE ALL (ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%',
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
      ]))
      AND (restaurants.company_name IS NULL OR restaurants.company_name NOT ILIKE ALL (ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%',
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
      ]))
      AND restaurants.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
      AND (
          1 = 0
          [[ OR (1 = 1 AND {{nome_do_restaurante}}) ]]
      )
),

clean_base AS (
    SELECT restaurant_id AS id FROM base_restaurants
),

logins_by_role AS (
    SELECT
        (access_history.restaurant_id::uuid) AS restaurant_id,
        MAX(CASE WHEN authentications.role = 'restaurant_admin'    THEN 1 ELSE 0 END) AS has_gestor_login,
        MAX(CASE WHEN authentications.role = 'restaurant_employee' THEN 1 ELSE 0 END) AS has_colab_login
    FROM access_history
    JOIN authentications ON authentications.login = access_history.login
    WHERE access_history.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
      AND access_history.restaurant_id IS NOT NULL
      AND access_history.restaurant_id ~ '^[0-9a-fA-F-]{36}$'
    GROUP BY access_history.restaurant_id
),
s1 AS (
    SELECT
        clean_base.id AS restaurant_id,
        COALESCE(logins_by_role.has_gestor_login, 0) AS has_gestor_login,
        COALESCE(logins_by_role.has_colab_login, 0) AS has_colab_login
    FROM clean_base
    LEFT JOIN logins_by_role ON clean_base.id = logins_by_role.restaurant_id
),

qualified_base_count AS (
    SELECT clean_base.id
    FROM clean_base
    JOIN enable_feature ON clean_base.id = enable_feature.restaurant_id
    WHERE enable_feature.count_products = TRUE
),
lists_with_controlled AS (
    SELECT DISTINCT inventory_list.restaurant_id, inventory_list.id AS inventory_list_id
    FROM inventory_list
    JOIN inventory_list_products ON inventory_list.id = inventory_list_products.inventory_list_id
    JOIN controlled_products ON controlled_products.product_id = inventory_list_products.product_id
    WHERE inventory_list.restaurant_id IN (SELECT qualified_base_count.id FROM qualified_base_count)
),
agg_s2 AS (
    SELECT restaurant_id, COUNT(DISTINCT inventory_list_id) AS lists_with_controlled_cnt
    FROM lists_with_controlled
    GROUP BY restaurant_id
),
s2 AS (
    SELECT
        qualified_base_count.id AS restaurant_id,
        CASE WHEN COALESCE(agg_s2.lists_with_controlled_cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_s2_lists_with_controlled
    FROM qualified_base_count
    LEFT JOIN agg_s2 ON qualified_base_count.id = agg_s2.restaurant_id
),

qualified_base_controlled AS (
    SELECT clean_base.id
    FROM clean_base
    JOIN enable_feature ON clean_base.id = enable_feature.restaurant_id
    WHERE enable_feature.controlled_products = TRUE
),
controlled_with_weight AS (
    SELECT controlled_products.restaurant_id, COUNT(DISTINCT controlled_products.id) AS controlled_weighted_cnt
    FROM controlled_products
    LEFT JOIN products ON controlled_products.product_id = products.id
    WHERE controlled_products.restaurant_id IN (SELECT qualified_base_controlled.id FROM qualified_base_controlled)
      AND COALESCE(products.weight, 0) > 0
    GROUP BY controlled_products.restaurant_id
),
s3 AS (
    SELECT
        qualified_base_controlled.id AS restaurant_id,
        CASE WHEN COALESCE(controlled_with_weight.controlled_weighted_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_s3_controlled_with_weight
    FROM qualified_base_controlled
    LEFT JOIN controlled_with_weight ON qualified_base_controlled.id = controlled_with_weight.restaurant_id
),

qualified_base AS (
    SELECT clean_base.id
    FROM clean_base
    JOIN enable_feature ON clean_base.id = enable_feature.restaurant_id
    WHERE enable_feature.production_tags = TRUE
),
prints_production AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos.tags_count, 1)) AS cnt
    FROM qualified_base
    JOIN tag_infos ON tag_infos.restaurant_id = qualified_base.id AND tag_infos.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qualified_base.id
),
prints_receivings AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos_receivings.tags_count, 1)) AS cnt
    FROM qualified_base
    JOIN tag_infos_receivings ON tag_infos_receivings.restaurant_id = qualified_base.id AND tag_infos_receivings.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qualified_base.id
),
e1 AS (
    SELECT
        qualified_base.id AS restaurant_id,
        CASE WHEN (COALESCE(prints_production.cnt, 0) + COALESCE(prints_receivings.cnt, 0)) >= 50 THEN 1 ELSE 0 END AS hit_e1_50_prints
    FROM qualified_base
    LEFT JOIN prints_production ON qualified_base.id = prints_production.restaurant_id
    LEFT JOIN prints_receivings ON qualified_base.id = prints_receivings.restaurant_id
),
controlled_prints_production AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos.tags_count, 1)) AS cnt
    FROM qualified_base
    JOIN tag_infos ON tag_infos.restaurant_id = qualified_base.id AND tag_infos.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tag_infos.controlled_product = TRUE
    GROUP BY qualified_base.id
),
controlled_prints_receivings AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos_receivings.tags_count, 1)) AS cnt
    FROM qualified_base
    JOIN tag_infos_receivings ON tag_infos_receivings.restaurant_id = qualified_base.id AND tag_infos_receivings.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tag_infos_receivings.controlled_product = TRUE
    GROUP BY qualified_base.id
),
e2 AS (
    SELECT
        qualified_base.id AS restaurant_id,
        CASE WHEN (COALESCE(controlled_prints_production.cnt, 0) + COALESCE(controlled_prints_receivings.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_e2_30_controlled_prints
    FROM qualified_base
    LEFT JOIN controlled_prints_production ON qualified_base.id = controlled_prints_production.restaurant_id
    LEFT JOIN controlled_prints_receivings ON qualified_base.id = controlled_prints_receivings.restaurant_id
),
baixas_production AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos.tags_count_removed, 0)) AS cnt
    FROM qualified_base
    JOIN tag_infos ON tag_infos.restaurant_id = qualified_base.id AND tag_infos.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qualified_base.id
),
baixas_receivings AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos_receivings.tags_count_removed, 0)) AS cnt
    FROM qualified_base
    JOIN tag_infos_receivings ON tag_infos_receivings.restaurant_id = qualified_base.id AND tag_infos_receivings.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qualified_base.id
),
e3 AS (
    SELECT
        qualified_base.id AS restaurant_id,
        CASE WHEN (COALESCE(baixas_production.cnt, 0) + COALESCE(baixas_receivings.cnt, 0)) >= 10 THEN 1 ELSE 0 END AS hit_e3_10_baixas
    FROM qualified_base
    LEFT JOIN baixas_production ON qualified_base.id = baixas_production.restaurant_id
    LEFT JOIN baixas_receivings ON qualified_base.id = baixas_receivings.restaurant_id
),
contagens_last_30d AS (
    SELECT qualified_base_count.id AS restaurant_id, COUNT(*) AS contagens_cnt
    FROM qualified_base_count
    JOIN inventory ON inventory.restaurant_id = qualified_base_count.id AND inventory.completed_at IS NOT NULL AND inventory.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY qualified_base_count.id
),
e4 AS (
    SELECT
        qualified_base_count.id AS restaurant_id,
        CASE WHEN COALESCE(contagens_last_30d.contagens_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_e4_5_contagens
    FROM qualified_base_count
    LEFT JOIN contagens_last_30d ON qualified_base_count.id = contagens_last_30d.restaurant_id
),

v1_production AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos.tags_count, 1)) AS cnt
    FROM qualified_base
    JOIN tag_infos ON tag_infos.restaurant_id = qualified_base.id AND tag_infos.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN restaurant_products ON restaurant_products.product_id = tag_infos.product_id AND restaurant_products.restaurant_id = tag_infos.restaurant_id
    JOIN products ON products.id = restaurant_products.product_id AND COALESCE(products.weight, 0) > 0
    GROUP BY qualified_base.id
),
v1_receivings AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos_receivings.tags_count, 1)) AS cnt
    FROM qualified_base
    JOIN tag_infos_receivings ON tag_infos_receivings.restaurant_id = qualified_base.id AND tag_infos_receivings.inserted_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN restaurant_products ON restaurant_products.product_id = tag_infos_receivings.product_id AND restaurant_products.restaurant_id = tag_infos_receivings.restaurant_id
    JOIN products ON products.id = restaurant_products.product_id AND COALESCE(products.weight, 0) > 0
    GROUP BY qualified_base.id
),
v2_production AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos.tags_count, 1)) AS cnt
    FROM qualified_base
    JOIN tag_infos ON tag_infos.restaurant_id = qualified_base.id AND tag_infos.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tag_infos.controlled_product = TRUE
    JOIN restaurant_products ON restaurant_products.product_id = tag_infos.product_id AND restaurant_products.restaurant_id = tag_infos.restaurant_id
    JOIN products ON products.id = restaurant_products.product_id AND COALESCE(products.weight, 0) > 0
    GROUP BY qualified_base.id
),
v2_receivings AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos_receivings.tags_count, 1)) AS cnt
    FROM qualified_base
    JOIN tag_infos_receivings ON tag_infos_receivings.restaurant_id = qualified_base.id AND tag_infos_receivings.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tag_infos_receivings.controlled_product = TRUE
    JOIN restaurant_products ON restaurant_products.product_id = tag_infos_receivings.product_id AND restaurant_products.restaurant_id = tag_infos_receivings.restaurant_id
    JOIN products ON products.id = restaurant_products.product_id AND COALESCE(products.weight, 0) > 0
    GROUP BY qualified_base.id
),
v3_production AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos.tags_count_removed, 0)) AS cnt
    FROM qualified_base
    JOIN tag_infos ON tag_infos.restaurant_id = qualified_base.id AND tag_infos.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tag_infos.controlled_product = TRUE
    JOIN restaurant_products ON restaurant_products.product_id = tag_infos.product_id AND restaurant_products.restaurant_id = tag_infos.restaurant_id
    JOIN products ON products.id = restaurant_products.product_id AND COALESCE(products.weight, 0) > 0
    GROUP BY qualified_base.id
),
v3_receivings AS (
    SELECT qualified_base.id AS restaurant_id, SUM(COALESCE(tag_infos_receivings.tags_count_removed, 0)) AS cnt
    FROM qualified_base
    JOIN tag_infos_receivings ON tag_infos_receivings.restaurant_id = qualified_base.id AND tag_infos_receivings.inserted_at >= (CURRENT_DATE - INTERVAL '30 days') AND tag_infos_receivings.controlled_product = TRUE
    JOIN restaurant_products ON restaurant_products.product_id = tag_infos_receivings.product_id AND restaurant_products.restaurant_id = tag_infos_receivings.restaurant_id
    JOIN products ON products.id = restaurant_products.product_id AND COALESCE(products.weight, 0) > 0
    GROUP BY qualified_base.id
),
inventories_with_controlled_weight AS (
    SELECT inventory.restaurant_id, inventory.id AS inventory_id
    FROM qualified_base_count
    JOIN inventory ON inventory.restaurant_id = qualified_base_count.id AND inventory.completed_at IS NOT NULL AND inventory.completed_at >= (CURRENT_DATE - INTERVAL '30 days')
    JOIN inventory_count ON inventory_count.inventory_id = inventory.id
    JOIN controlled_products ON controlled_products.restaurant_id = inventory.restaurant_id AND controlled_products.product_id = inventory_count.product_id
    JOIN products ON products.id = controlled_products.product_id AND COALESCE(products.weight, 0) > 0
    GROUP BY inventory.restaurant_id, inventory.id
),
v4_per_restaurant AS (
    SELECT restaurant_id, COUNT(DISTINCT inventory_id) AS cnt
    FROM inventories_with_controlled_weight
    GROUP BY restaurant_id
),
value_metrics AS (
    SELECT
        clean_base.id AS restaurant_id,
        CASE WHEN (COALESCE(v1_production.cnt, 0) + COALESCE(v1_receivings.cnt, 0)) >= 20 THEN 1 ELSE 0 END AS hit_v1_20_prints_weight,
        CASE WHEN (COALESCE(v2_production.cnt, 0) + COALESCE(v2_receivings.cnt, 0)) >= 30 THEN 1 ELSE 0 END AS hit_v2_30_controlled_weight,
        CASE WHEN (COALESCE(v3_production.cnt, 0) + COALESCE(v3_receivings.cnt, 0)) >= 5 THEN 1 ELSE 0 END AS hit_v3_5_baixas_controlled_weight,
        CASE WHEN COALESCE(v4_per_restaurant.cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_v4_2_contagens_controlled_weight,
        CASE
            WHEN (COALESCE(v2_production.cnt, 0) + COALESCE(v2_receivings.cnt, 0)) >= 30
              OR (COALESCE(v3_production.cnt, 0) + COALESCE(v3_receivings.cnt, 0)) >= 5
              OR COALESCE(v4_per_restaurant.cnt, 0) >= 2
            THEN 1
            ELSE 0
        END AS has_weighted_controlled_core_action
    FROM clean_base
    LEFT JOIN v1_production ON clean_base.id = v1_production.restaurant_id
    LEFT JOIN v1_receivings ON clean_base.id = v1_receivings.restaurant_id
    LEFT JOIN v2_production ON clean_base.id = v2_production.restaurant_id
    LEFT JOIN v2_receivings ON clean_base.id = v2_receivings.restaurant_id
    LEFT JOIN v3_production ON clean_base.id = v3_production.restaurant_id
    LEFT JOIN v3_receivings ON clean_base.id = v3_receivings.restaurant_id
    LEFT JOIN v4_per_restaurant ON clean_base.id = v4_per_restaurant.restaurant_id
),

per_restaurant_scores AS (
    SELECT
        base_restaurants.restaurant_id,
        COALESCE(s1.has_gestor_login, 0) AS pts_s1_gestor,
        COALESCE(s1.has_colab_login, 0) AS pts_s1_colaborador,
        COALESCE(s2.hit_s2_lists_with_controlled, 0) * 3 AS pts_s2_lists_with_controlled,
        COALESCE(s3.hit_s3_controlled_with_weight, 0) * 5 AS pts_s3_controlled_with_weight,
        COALESCE(e1.hit_e1_50_prints, 0) * 3 AS pts_e1_50_prints,
        COALESCE(e2.hit_e2_30_controlled_prints, 0) * 7 AS pts_e2_30_controlled_prints,
        COALESCE(e3.hit_e3_10_baixas, 0) * 15 AS pts_e3_10_baixas,
        COALESCE(e4.hit_e4_5_contagens, 0) * 5 AS pts_e4_5_contagens,
        COALESCE(value_metrics.hit_v1_20_prints_weight, 0) * 15 AS pts_v1_20_prints_weight,
        COALESCE(value_metrics.hit_v2_30_controlled_weight, 0) * 10 AS pts_v2_30_controlled_weight,
        COALESCE(value_metrics.hit_v3_5_baixas_controlled_weight, 0) * 25 AS pts_v3_5_baixas_controlled_weight,
        COALESCE(value_metrics.hit_v4_2_contagens_controlled_weight, 0) * 10 AS pts_v4_2_contagens_controlled_weight,
        (
            COALESCE(s1.has_gestor_login, 0) +
            COALESCE(s1.has_colab_login, 0) +
            COALESCE(s2.hit_s2_lists_with_controlled, 0) * 3 +
            COALESCE(s3.hit_s3_controlled_with_weight, 0) * 5 +
            COALESCE(e1.hit_e1_50_prints, 0) * 3 +
            COALESCE(e2.hit_e2_30_controlled_prints, 0) * 7 +
            COALESCE(e3.hit_e3_10_baixas, 0) * 15 +
            COALESCE(e4.hit_e4_5_contagens, 0) * 5 +
            COALESCE(value_metrics.hit_v1_20_prints_weight, 0) * 15 +
            COALESCE(value_metrics.hit_v2_30_controlled_weight, 0) * 10 +
            COALESCE(value_metrics.hit_v3_5_baixas_controlled_weight, 0) * 25 +
            COALESCE(value_metrics.hit_v4_2_contagens_controlled_weight, 0) * 10
        ) AS total_score,
        COALESCE(value_metrics.has_weighted_controlled_core_action, 0) AS has_weighted_controlled_core_action
    FROM base_restaurants
    LEFT JOIN s1 ON base_restaurants.restaurant_id = s1.restaurant_id
    LEFT JOIN s2 ON base_restaurants.restaurant_id = s2.restaurant_id
    LEFT JOIN s3 ON base_restaurants.restaurant_id = s3.restaurant_id
    LEFT JOIN e1 ON base_restaurants.restaurant_id = e1.restaurant_id
    LEFT JOIN e2 ON base_restaurants.restaurant_id = e2.restaurant_id
    LEFT JOIN e3 ON base_restaurants.restaurant_id = e3.restaurant_id
    LEFT JOIN e4 ON base_restaurants.restaurant_id = e4.restaurant_id
    LEFT JOIN value_metrics ON base_restaurants.restaurant_id = value_metrics.restaurant_id
),

final AS (
    SELECT
        per_restaurant_scores.*,
        CASE
            WHEN per_restaurant_scores.total_score >= 80 AND per_restaurant_scores.has_weighted_controlled_core_action = 1 THEN 'green_activated'
            WHEN per_restaurant_scores.total_score >= 80 AND per_restaurant_scores.has_weighted_controlled_core_action = 0 THEN 'orange_false_positive'
            WHEN per_restaurant_scores.total_score BETWEEN 40 AND 79 THEN 'yellow_at_risk'
            ELSE 'red_failure'
        END AS activation_bucket
    FROM per_restaurant_scores
)

SELECT
    restaurants.trading_name AS "Trading name",
    final.restaurant_id AS "Restaurant ID",

    CASE WHEN final.pts_s1_gestor > 0 THEN '✅' ELSE '❌' END AS "Setup · Login gestor",
    CASE WHEN final.pts_s1_colaborador > 0 THEN '✅' ELSE '❌' END AS "Setup · Login colaborador",
    CASE WHEN final.pts_s2_lists_with_controlled > 0 THEN '✅' ELSE '❌' END AS "Setup · Listas c/ prod. controlado",
    CASE WHEN final.pts_s3_controlled_with_weight > 0 THEN '✅' ELSE '❌' END AS "Setup · Controlados c/ peso",

    CASE WHEN final.pts_e1_50_prints > 0 THEN '✅' ELSE '❌' END AS "Effort · 50 impressões",
    CASE WHEN final.pts_e2_30_controlled_prints > 0 THEN '✅' ELSE '❌' END AS "Effort · 30 imp. controladas",
    CASE WHEN final.pts_e3_10_baixas > 0 THEN '✅' ELSE '❌' END AS "Effort · 10 baixas",
    CASE WHEN final.pts_e4_5_contagens > 0 THEN '✅' ELSE '❌' END AS "Effort · 5 contagens",

    CASE WHEN final.pts_v1_20_prints_weight > 0 THEN '✅' ELSE '❌' END AS "Value · 20 impressões c/ peso (shared)",
    CASE WHEN final.pts_v2_30_controlled_weight > 0 THEN '✅' ELSE '❌' END AS "Value · 30 imp. control. c/ peso",
    CASE WHEN final.pts_v3_5_baixas_controlled_weight > 0 THEN '✅' ELSE '❌' END AS "Value · 5 baixas control. c/ peso",
    CASE WHEN final.pts_v4_2_contagens_controlled_weight > 0 THEN '✅' ELSE '❌' END AS "Value · 2 contagens c/ peso"

FROM final
JOIN restaurants ON restaurants.id = final.restaurant_id;
