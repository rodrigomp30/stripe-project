-- Activation Health Score – Setup Bucket (Intermediate Model)
--
-- One row per restaurant that has at least one Setup metric (S1, S2, or S3).
-- Does NOT define the cohort; consolidation defines base_restaurants and LEFT JOINs this.
-- Outputs: restaurant_id, S1/S2/S3 hit flags (and optional raw counts).
-- Logic from viability_tests/activation_setup_metrics.sql (S1 v2, S2 v2, S2 v2).

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

-- S1: ≥ 1 login gestor + ≥ 1 login colaborador (restaurants with login data in 30 days)
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
      AND (ah.restaurant_id::uuid) IN (SELECT id FROM hygiene_restaurant_ids)
    GROUP BY ah.restaurant_id
),
s1 AS (
    SELECT
        restaurant_id,
        COALESCE(has_gestor_login, 0) AS has_gestor_login,
        COALESCE(has_colab_login, 0) AS has_colab_login,
        CASE
            WHEN COALESCE(has_gestor_login, 0) = 1 AND COALESCE(has_colab_login, 0) = 1 THEN 1
            ELSE 0
        END AS hit_s1_logins
    FROM logins_by_role
),

-- S2: ≥ 2 listas com ≥ 1 produto controlado cada (base: count_products)
qualified_base_count AS (
    SELECT h.id
    FROM hygiene_restaurant_ids h
    JOIN enable_feature ef ON ef.restaurant_id = h.id
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
        COALESCE(a.lists_with_controlled_cnt, 0) AS lists_with_controlled_cnt,
        CASE WHEN COALESCE(a.lists_with_controlled_cnt, 0) >= 2 THEN 1 ELSE 0 END AS hit_s2_lists_with_controlled
    FROM qualified_base_count qb
    LEFT JOIN agg_s2 a ON qb.id = a.restaurant_id
),

-- S3: ≥ 5 produtos controlados com peso (base: controlled_products)
qualified_base_controlled AS (
    SELECT h.id
    FROM hygiene_restaurant_ids h
    JOIN enable_feature ef ON ef.restaurant_id = h.id
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
        COALESCE(cw.controlled_weighted_cnt, 0) AS controlled_weighted_cnt,
        CASE WHEN COALESCE(cw.controlled_weighted_cnt, 0) >= 5 THEN 1 ELSE 0 END AS hit_s3_controlled_with_weight
    FROM qualified_base_controlled qb
    LEFT JOIN controlled_with_weight cw ON qb.id = cw.restaurant_id
),

all_restaurant_ids AS (
    SELECT restaurant_id FROM s1
    UNION
    SELECT restaurant_id FROM s2
    UNION
    SELECT restaurant_id FROM s3
)

SELECT
    a.restaurant_id,
    COALESCE(s1.hit_s1_logins, 0) AS hit_s1_logins,
    COALESCE(s2.lists_with_controlled_cnt, 0) AS lists_with_controlled_cnt,
    COALESCE(s2.hit_s2_lists_with_controlled, 0) AS hit_s2_lists_with_controlled,
    COALESCE(s3.controlled_weighted_cnt, 0) AS controlled_weighted_cnt,
    COALESCE(s3.hit_s3_controlled_with_weight, 0) AS hit_s3_controlled_with_weight
FROM all_restaurant_ids a
LEFT JOIN s1 ON a.restaurant_id = s1.restaurant_id
LEFT JOIN s2 ON a.restaurant_id = s2.restaurant_id
LEFT JOIN s3 ON a.restaurant_id = s3.restaurant_id;
