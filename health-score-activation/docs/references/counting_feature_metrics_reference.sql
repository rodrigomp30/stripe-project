-- Counting Feature Metrics – Reference Queries
-- 
-- Reference patterns for: clean_base, enable_feature, inventory_list, inventory_count.
-- Copy from here when building activation health score queries in models/intermediate or viability_tests.

/* ============================================================================
   Metric 1: Restaurants that created ≥ 1 inventory list with ≥ 1 product
   ==========================================================================*/

WITH qualified_base_sample AS (
    SELECT r.id
    FROM restaurants r 
    JOIN enable_feature ef ON r.id = ef.restaurant_id
    WHERE 
        r.deleted_at IS NULL 
        AND r.is_blocked IS FALSE
        AND (r.email IS NULL OR r.email NOT ILIKE '%suflex%')
        AND (r.trading_name IS NULL OR r.trading_name NOT ILIKE ALL(ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', 
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]))
        AND (r.company_name IS NULL OR r.company_name NOT ILIKE ALL(ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', 
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]))
        AND ef.count_products = TRUE
),
active_users_check AS (
    SELECT DISTINCT il.restaurant_id
    FROM inventory_list il
    JOIN inventory_list_products ilp ON il.id = ilp.inventory_list_id
    WHERE il.restaurant_id IN (SELECT id FROM qualified_base_sample)
)
SELECT 
    ROUND(
        (COUNT(auc.restaurant_id)::NUMERIC / COUNT(*)) * 100, 
    2) AS "Utilization Rate (%)"
FROM qualified_base_sample qbs
LEFT JOIN active_users_check auc ON qbs.id = auc.restaurant_id;


/* ============================================================================
   Metric 2: Same base as Metric 1, with additional counts
   ==========================================================================*/

WITH clean_base AS (
    SELECT r.id
    FROM restaurants r
    WHERE 
        r.deleted_at IS NULL 
        AND r.is_blocked IS FALSE
        AND (r.email IS NULL OR r.email NOT ILIKE '%suflex%')
        AND (r.trading_name IS NULL OR r.trading_name NOT ILIKE ALL(ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', 
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]))
        AND (r.company_name IS NULL OR r.company_name NOT ILIKE ALL(ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', 
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]))
),
qualified_base_sample AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.count_products = TRUE
),
active_users_check AS (
    SELECT DISTINCT il.restaurant_id
    FROM inventory_list il
    JOIN inventory_list_products ilp ON il.id = ilp.inventory_list_id
    WHERE il.restaurant_id IN (SELECT id FROM qualified_base_sample)
),
total_stats AS (
    SELECT COUNT(*) AS total_clean_base FROM clean_base
)
SELECT 
    ts.total_clean_base AS "Base Total (Limpa)",
    COUNT(qbs.id) AS "Restaurantes com Contagem Habilitada",
    COUNT(auc.restaurant_id) AS "Restaurantes com Setup feito | (≥1 lista com ≥1 produto)",
    ROUND((COUNT(qbs.id)::NUMERIC / NULLIF(ts.total_clean_base, 0)) * 100, 2) AS "% Habilitados na Base",
    ROUND((COUNT(auc.restaurant_id)::NUMERIC / NULLIF(COUNT(qbs.id), 0)) * 100, 2) AS "% Fizeram Setup (dos Habilitados)"
FROM qualified_base_sample qbs
LEFT JOIN active_users_check auc ON qbs.id = auc.restaurant_id
CROSS JOIN total_stats ts
GROUP BY ts.total_clean_base;


/* ============================================================================
   Metric 3: Restaurants that finalized at least 1 inventory count
   ==========================================================================*/

WITH clean_base AS (
    SELECT r.id
    FROM restaurants r
    WHERE 
        r.deleted_at IS NULL 
        AND r.is_blocked IS FALSE
        AND (r.email IS NULL OR r.email NOT ILIKE '%suflex%')
        AND (r.trading_name IS NULL OR r.trading_name NOT ILIKE ALL(ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', 
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]))
        AND (r.company_name IS NULL OR r.company_name NOT ILIKE ALL(ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', 
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]))
),
qualified_base_sample AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.count_products = TRUE
),
active_users_check AS (
    SELECT DISTINCT il.restaurant_id
    FROM inventory_list il
    JOIN inventory_list_products ilp ON il.id = ilp.inventory_list_id
    WHERE il.restaurant_id IN (SELECT id FROM qualified_base_sample)
),
counters_check AS (
    SELECT DISTINCT i.restaurant_id
    FROM inventory i
    JOIN inventory_count ic ON i.id = ic.inventory_id
    WHERE i.restaurant_id IN (SELECT restaurant_id FROM active_users_check)
      AND i.completed_at IS NOT NULL
),
total_stats AS (
    SELECT COUNT(*) AS total_clean_base FROM clean_base
)
SELECT 
    ROUND(
        (COUNT(cc.restaurant_id)::NUMERIC / NULLIF(COUNT(auc.restaurant_id), 0)) * 100, 
    1) AS "% Conversão (Setup -> Contagem)"
FROM qualified_base_sample qbs
LEFT JOIN active_users_check auc ON qbs.id = auc.restaurant_id
LEFT JOIN counters_check cc ON qbs.id = cc.restaurant_id
CROSS JOIN total_stats ts 
GROUP BY ts.total_clean_base;


/* ============================================================================
   Metric 4: Same as 3, with additional counts
   ==========================================================================*/

WITH clean_base AS (
    SELECT r.id
    FROM restaurants r
    WHERE 
        r.deleted_at IS NULL 
        AND r.is_blocked IS FALSE
        AND (r.email IS NULL OR r.email NOT ILIKE '%suflex%')
        AND (r.trading_name IS NULL OR r.trading_name NOT ILIKE ALL(ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', 
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]))
        AND (r.company_name IS NULL OR r.company_name NOT ILIKE ALL(ARRAY[
            '%suflex%', '%homolog%', '%lab%', '%fechado%', '%foodcamp%', 
            '%restaurante do arthur%', '%treinamento%', '%produto%', '%time%'
        ]))
),
qualified_base_sample AS (
    SELECT cb.id
    FROM clean_base cb
    JOIN enable_feature ef ON cb.id = ef.restaurant_id
    WHERE ef.count_products = TRUE
),
active_users_check AS (
    SELECT DISTINCT il.restaurant_id
    FROM inventory_list il
    JOIN inventory_list_products ilp ON il.id = ilp.inventory_list_id
    WHERE il.restaurant_id IN (SELECT id FROM qualified_base_sample)
),
counters_check AS (
    SELECT DISTINCT i.restaurant_id
    FROM inventory i
    JOIN inventory_count ic ON i.id = ic.inventory_id
    WHERE i.restaurant_id IN (SELECT restaurant_id FROM active_users_check)
      AND i.completed_at IS NOT NULL
),
total_stats AS (
    SELECT COUNT(*) AS total_clean_base FROM clean_base
)
SELECT 
    COUNT(auc.restaurant_id) AS "Restaurantes com Setup feito",
    COUNT(cc.restaurant_id) AS "Restaurantes Ativos | (≥1 Contagem Finalizada)",
    ROUND((COUNT(cc.restaurant_id)::NUMERIC / NULLIF(COUNT(auc.restaurant_id), 0)) * 100, 1) AS "% Conversão (Setup -> Ativação)"
FROM qualified_base_sample qbs
LEFT JOIN active_users_check auc ON qbs.id = auc.restaurant_id
LEFT JOIN counters_check cc ON qbs.id = cc.restaurant_id
CROSS JOIN total_stats ts 
GROUP BY ts.total_clean_base;
