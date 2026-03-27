-- Activation – Setup Bucket Metrics (Viability Queries)
-- 
-- Run with or without EXPLAIN in DBeaver to validate feasibility of Setup milestones.
-- Source for S1: access_history + authentications.role (permission granted).

/* ============================================================================
   DIAGNOSTIC – Base size: clean_base vs qualified_base (enable_feature)
   ---------------------------------------------------------------------------
   S1 uses clean_base only (no feature flag). Other metrics use qualified_base
   (clean_base + enable_feature for a given feature). If you saw 50 before
   and 123 now, the difference is likely enable_feature (50 = with flag, 123 = all).
   ==========================================================================*/

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
with_production_tags AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON ef.restaurant_id = cb.id
    WHERE ef.production_tags = TRUE
),
with_count_products AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON ef.restaurant_id = cb.id
    WHERE ef.count_products = TRUE
)
SELECT
    (SELECT COUNT(*) FROM clean_base)                    AS "clean_base (S1 – no feature flag)",
    (SELECT COUNT(*) FROM with_production_tags)          AS "qualified_base production_tags",
    (SELECT COUNT(*) FROM with_count_products)           AS "qualified_base count_products";

-- Uncomment to see distribution by week (who joined when):
/*
WITH time_window AS (
    SELECT (CURRENT_DATE - INTERVAL '30 days') AS start_date
),
clean_base AS (
    SELECT r.id, r.inserted_at
    FROM restaurants r
    CROSS JOIN time_window tw
    WHERE r.deleted_at IS NULL AND r.is_blocked IS FALSE
      AND (r.email IS NULL OR r.email NOT ILIKE '%suflex%')
      AND (r.trading_name IS NULL OR r.trading_name NOT ILIKE ALL (ARRAY['%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%']))
      AND (r.company_name IS NULL OR r.company_name NOT ILIKE ALL (ARRAY['%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%']))
      AND r.inserted_at >= tw.start_date
)
SELECT
    DATE_TRUNC('week', cb.inserted_at)::date AS "Week start",
    COUNT(*) AS "Restaurants created"
FROM clean_base cb
GROUP BY 1
ORDER BY 1;
*/

/* ============================================================================
   Metric S1 – ≥ 1 login gestor + ≥ 1 login colaborador (1 + 1 pt)
   ---------------------------------------------------------------------------
   Logins within TTVW; gestor = restaurant_admin, colaborador = restaurant_employee.
   access_history.restaurant_id is varchar – cast to uuid when joining.
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

logins_by_role AS (
    SELECT
        (ah.restaurant_id::uuid) AS restaurant_id,
        MAX(CASE WHEN a.role = 'restaurant_admin'    THEN 1 ELSE 0 END) AS has_gestor_login,
        MAX(CASE WHEN a.role = 'restaurant_employee' THEN 1 ELSE 0 END) AS has_colab_login
    FROM access_history ah
    JOIN authentications a ON a.login = ah.login
    CROSS JOIN time_window tw
    WHERE ah.inserted_at >= tw.start_date
      AND ah.restaurant_id IS NOT NULL
      AND ah.restaurant_id ~ '^[0-9a-fA-F-]{36}$'
    GROUP BY ah.restaurant_id
)

SELECT
    COUNT(cb.id) AS "Base (Restaurantes no período)",
    COUNT(l.restaurant_id) AS "Rests com ≥1 login (qualquer papel)",
    COUNT(*) FILTER (WHERE l.has_gestor_login = 1) AS "Rests com ≥1 login gestor",
    COUNT(*) FILTER (WHERE l.has_colab_login = 1) AS "Rests com ≥1 login colaborador",
    COUNT(*) FILTER (WHERE l.has_gestor_login = 1 AND l.has_colab_login = 1) AS "Rests com gestor + colaborador",
    ROUND(
        (COUNT(*) FILTER (WHERE l.has_gestor_login = 1 AND l.has_colab_login = 1)::NUMERIC
         / NULLIF(COUNT(cb.id), 0)) * 100, 2
    ) AS "% que atingem S1 (gestor + colab)"
FROM clean_base cb
LEFT JOIN logins_by_role l ON cb.id = l.restaurant_id;


/* ============================================================================
   Metric S1 – v2 (per-restaurant flags for consolidation)
   ---------------------------------------------------------------------------
   Same logic as S1 above, but returns one row per restaurant with:
   - has_gestor_login, has_colab_login (0/1)
   - hit_s1_logins (1 if both gestor and colaborador, else 0)
   ==========================================================================*/

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

logins_by_role AS (
    SELECT
        (ah.restaurant_id::uuid) AS restaurant_id,
        MAX(CASE WHEN a.role = 'restaurant_admin'    THEN 1 ELSE 0 END) AS has_gestor_login,
        MAX(CASE WHEN a.role = 'restaurant_employee' THEN 1 ELSE 0 END) AS has_colab_login
    FROM access_history ah
    JOIN authentications a ON a.login = ah.login
    CROSS JOIN time_window tw
    WHERE ah.inserted_at >= tw.start_date
      AND ah.restaurant_id IS NOT NULL
      AND ah.restaurant_id ~ '^[0-9a-fA-F-]{36}$'
    GROUP BY ah.restaurant_id
)

SELECT
    cb.id AS restaurant_id,
    COALESCE(l.has_gestor_login, 0) AS has_gestor_login,
    COALESCE(l.has_colab_login, 0) AS has_colab_login,
    CASE
        WHEN COALESCE(l.has_gestor_login, 0) = 1 AND COALESCE(l.has_colab_login, 0) = 1 THEN 1
        ELSE 0
    END AS hit_s1_logins
FROM clean_base cb
LEFT JOIN logins_by_role l ON cb.id = l.restaurant_id;


/* ============================================================================
   Metric S2 – ≥ 2 inventory lists with ≥ 1 controlled product each
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
    WHERE ef.count_products = TRUE
),

lists_with_controlled AS (
    SELECT DISTINCT
        il.restaurant_id,
        il.id AS inventory_list_id
    FROM inventory_list il
    JOIN inventory_list_products ilp
      ON il.id = ilp.inventory_list_id
    JOIN controlled_products cp
      ON cp.product_id = ilp.product_id
    WHERE il.restaurant_id IN (SELECT id FROM qualified_base)
),

agg_per_restaurant AS (
    SELECT
        restaurant_id,
        COUNT(DISTINCT inventory_list_id) AS lists_with_controlled_cnt
    FROM lists_with_controlled
    GROUP BY restaurant_id
)

SELECT
    COUNT(qb.id) AS "Base (Habilitados para Contagem)",
    COUNT(a.restaurant_id) AS "Rests com ≥1 Lista com Controlados",
    COUNT(*) FILTER (
        WHERE a.lists_with_controlled_cnt >= 2
    ) AS "Rests com ≥2 Listas com Controlados",
    ROUND(
        (COUNT(*) FILTER (WHERE a.lists_with_controlled_cnt >= 2)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥2 listas)"
FROM qualified_base qb
LEFT JOIN agg_per_restaurant a ON qb.id = a.restaurant_id;


/* ============================================================================
   Metric S2 – v2 (per-restaurant flags for consolidation)
   ---------------------------------------------------------------------------
   Same logic as S2 above, but returns one row per restaurant with:
   - lists_with_controlled_cnt
   - hit_s2_lists_with_controlled (0/1 flag)
   Use this as input to the final consolidation query.
   ==========================================================================*/

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
    WHERE ef.count_products = TRUE
),

lists_with_controlled AS (
    SELECT DISTINCT
        il.restaurant_id,
        il.id AS inventory_list_id
    FROM inventory_list il
    JOIN inventory_list_products ilp
      ON il.id = ilp.inventory_list_id
    JOIN controlled_products cp
      ON cp.product_id = ilp.product_id
    WHERE il.restaurant_id IN (SELECT id FROM qualified_base)
),

agg_per_restaurant AS (
    SELECT
        restaurant_id,
        COUNT(DISTINCT inventory_list_id) AS lists_with_controlled_cnt
    FROM lists_with_controlled
    GROUP BY restaurant_id
)

SELECT
    qb.id AS restaurant_id,
    COALESCE(a.lists_with_controlled_cnt, 0) AS lists_with_controlled_cnt,
    CASE 
        WHEN COALESCE(a.lists_with_controlled_cnt, 0) >= 2 THEN 1 
        ELSE 0 
    END AS hit_s2_lists_with_controlled
FROM qualified_base qb
LEFT JOIN agg_per_restaurant a ON qb.id = a.restaurant_id;


/* ============================================================================
   Metric S3 – ≥ 5 controlled products with weight
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
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.controlled_products = TRUE
),

controlled_with_weight AS (
    SELECT
        cp.restaurant_id,
        COUNT(DISTINCT cp.id) AS controlled_weighted_cnt
    FROM controlled_products cp
    LEFT JOIN products p
      ON cp.product_id = p.id
    WHERE cp.restaurant_id IN (SELECT id FROM qualified_base)
      AND COALESCE(p.weight, 0) > 0
    GROUP BY cp.restaurant_id
)

SELECT
    COUNT(qb.id) AS "Base (Controlados Habilitados)",
    COUNT(cw.restaurant_id) AS "Rests com ≥1 Produto Controlado com Peso",
    COUNT(*) FILTER (
        WHERE cw.controlled_weighted_cnt >= 5
    ) AS "Rests com ≥5 Produtos Controlados com Peso",
    ROUND(
        (COUNT(*) FILTER (WHERE cw.controlled_weighted_cnt >= 5)::NUMERIC
         / NULLIF(COUNT(qb.id), 0)) * 100, 2
    ) AS "% que atingem o marco (≥5 produtos)"
FROM qualified_base qb
LEFT JOIN controlled_with_weight cw ON qb.id = cw.restaurant_id;


/* ============================================================================
   Metric S3 – v2 (per-restaurant flags for consolidation)
   ---------------------------------------------------------------------------
   Same logic as S3 above, but returns one row per restaurant with:
   - controlled_weighted_cnt
   - hit_s3_controlled_with_weight (0/1 flag)
   Use this as input to the final consolidation query.
   ==========================================================================*/

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
),

qualified_base AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.controlled_products = TRUE
),

controlled_with_weight AS (
    SELECT
        cp.restaurant_id,
        COUNT(DISTINCT cp.id) AS controlled_weighted_cnt
    FROM controlled_products cp
    LEFT JOIN products p
      ON cp.product_id = p.id
    WHERE cp.restaurant_id IN (SELECT id FROM qualified_base)
      AND COALESCE(p.weight, 0) > 0
    GROUP BY cp.restaurant_id
)

SELECT
    qb.id AS restaurant_id,
    COALESCE(cw.controlled_weighted_cnt, 0) AS controlled_weighted_cnt,
    CASE
        WHEN COALESCE(cw.controlled_weighted_cnt, 0) >= 5 THEN 1
        ELSE 0
    END AS hit_s3_controlled_with_weight
FROM qualified_base qb
LEFT JOIN controlled_with_weight cw ON qb.id = cw.restaurant_id;

