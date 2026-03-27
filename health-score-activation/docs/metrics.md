## Metrics Definitions – Activation and Health Score

This file describes **business-facing metric definitions** for Suflex’s Activation Health Score. The structured spec (YAML) is in `docs/references/activation_health_score.yml`.

### Core activation metrics

- **Activation health score (per restaurant)**:
  - **What it is**: A 0–100 score that measures how far a restaurant progresses through the activation journey during the 30-day Time-to-Value Window.
  - **How it is built**: Sum of points from three buckets:
    - Setup (max 10 pts).
    - Effort & Commitment (max 30 pts).
    - Value Capture (max 60 pts).
  - **SQL location**: Final implementation will live in `models/marts/activation/mart_activation_health_score.sql`.

- **Activated restaurant (boolean)**:
  - **Business rule**: At the end of the 30-day window, a restaurant is Activated if:
    - Total activation score ≥ 80 (Lock), **and**
    - It has performed at least one qualified value-capture action involving controlled products with weight (Key).
  - **SQL rule**: `is_activated = (total_score >= 80 AND has_weighted_controlled_core_action = TRUE)`.

- **Activation rate**:
  - **Numerator**: Count of restaurants in a given cohort whose `is_activated = TRUE` by the end of their TTVW.
  - **Denominator**: Count of valid restaurants in that cohort (e.g. all new onboarded restaurants that pass hygiene filters).
  - **Filters / segments**: Can be sliced by plan, brand, region, onboarding channel, etc.

### Buckets for CS / onboarding

These are derived from the health score and the Key condition:

- **Activated (Green)**:
  - Condition: `total_score >= 80` **and** `has_weighted_controlled_core_action = TRUE`.
  - Interpretation: Setup done, repeated usage, and clear financial ROI actions.

- **Alert – False Positive (Orange)**:
  - Condition: `total_score >= 80` **and** `has_weighted_controlled_core_action = FALSE`.
  - Interpretation: Heavy usage of low-value behaviors (e.g. printing) without controlled, weighted actions; CS should intervene.

- **At-Risk (Yellow)**:
  - Condition: `40 <= total_score < 80`.
  - Interpretation: Setup and some usage exist but the restaurant is stuck before fully closing the value loop.

- **Failure (Red)**:
  - Condition: `total_score < 40`.
  - Interpretation: Minimal or no engagement; onboarding essentially failed.

These buckets are expected to be materialized as columns in the final mart (e.g. `activation_bucket`) and used directly in Metabase dashboards and CS views.

---

## Viability tracking – per-metric status

Use this section to track which Activation Health Score milestones have been tested on the production snapshot, and any relevant observations.

### Setup bucket (max 10 pts)

- **S1 – ≥ 1 login gestor + ≥ 1 login colaborador (1 + 1 pt)**  
  - **Definition**: ≥ 1 login from `restaurant_admin` AND ≥ 1 login from `restaurant_employee` within the TTVW.  
  - **Status**: **Viability tested (OK)**.  
  - **Source**: `access_history` + `authentications.role` (`restaurant_admin` = gestor, `restaurant_employee` = colaborador).  
  - **Query**: `viability_tests/activation_setup_metrics.sql` (S1, S1 v2).

- **S2 – ≥ 2 listas de contagem com ≥ 1 produto controlado cada (3 pts)**  
  - **Definition**: ≥ 2 `inventory_list` per restaurant, each with ≥ 1 product in `controlled_products`.  
  - **Status**: **Viability tested (OK)**.  
  - **Query**: `viability_tests/activation_setup_metrics.sql` (S2).  

- **S3 – ≥ 5 produtos controlados cadastrados com peso (5 pts)**  
  - **Definition**: ≥ 5 `controlled_products` per restaurant where `products.weight > 0`.  
  - **Status**: **Viability tested (OK)**.  
  - **Query**: `viability_tests/activation_setup_metrics.sql` (S3).

### Effort & Commitment bucket (max 30 pts)

- **E1 – 50 impressões (3 pts)**  
  - **Status**: **Viability tested (OK)**.  
  - **Query**: `viability_tests/activation_effort_metrics.sql` (E1 v4; use tag_infos + tag_infos_receivings, drive from qualified_base for cost &lt;500k).

- **E2 – 30 impressões de produtos controlados (7 pts)**  
  - **Status**: **Viability tested (OK)**.  
  - **Query**: `viability_tests/activation_effort_metrics.sql` (E2; tag_infos + tag_infos_receivings, controlled_product = TRUE, drive from qualified_base).

- **E3 – 10 baixas realizadas (15 pts)**  
  - **Status**: **Viability tested (OK)**.  
  - **Source**: `tag_infos` + `tag_infos_receivings`, `SUM(COALESCE(tags_count_removed, 0))` per restaurant (baixas = tags_count_removed per project rules).  
  - **Query**: `viability_tests/activation_effort_metrics.sql` (E3; drive from qualified_base, 30-day window).

- **E4 – 5 contagens (5 pts)**  
  - **Status**: **Viability tested (OK)**.  
  - **Source**: `inventory` with `completed_at IS NOT NULL` and `completed_at` in last 30 days; one contagem = one completed inventory. Base: `qualified_base_count` (count_products = TRUE).  
  - **Query**: `viability_tests/activation_effort_metrics.sql` (E4). Ref: `docs/references/counting_feature_metrics_reference.sql` (Metric 3/4).

### Value Capture bucket (max 60 pts)

- **V1 – 20 impressões com peso (15 pts)**  
  - **Status**: **Viability tested (OK)**.  
  - **Source**: `tag_infos` + `tag_infos_receivings` via `restaurant_products` (restaurant_id) then `products` where `COALESCE(products.weight, 0) > 0`; sum `tags_count` per restaurant. Base: qualified_base (production_tags). Playbook: shared products.  
  - **Query**: `viability_tests/activation_value_metrics.sql` (V1).

- **V2 – 30 impressões de produtos controlados com peso (10 pts)**  
  - **Status**: **Viability tested (OK)**.  
  - **Source**: Same as V1 with `controlled_product = TRUE`; via `restaurant_products` + `products.weight > 0` (playbook: shared products).  
  - **Query**: `viability_tests/activation_value_metrics.sql` (V2).

- **V3 – 5 baixas de etiquetas de produtos controlados com peso (25 pts)**  
  - **Status**: **Viability tested (OK)**.  
  - **Source**: `tag_infos` + `tag_infos_receivings`, `controlled_product = TRUE`, via `restaurant_products` + `products.weight > 0`; `SUM(tags_count_removed)` per restaurant (playbook: shared products).  
  - **Query**: `viability_tests/activation_value_metrics.sql` (V3).

- **V4 – 2 contagens com ≥ 1 produto controlado cada, com peso (10 pts)**  
  - **Status**: **Viability tested (OK)**.  
  - **Source**: Completed `inventory` in last 30 days; count distinct inventories that have ≥1 `inventory_count` row whose product is in `controlled_products` and has `products.weight > 0`. Base: qualified_base_count (count_products).  
  - **Query**: `viability_tests/activation_value_metrics.sql` (V4).

- **Key (activation lock)**: `has_weighted_controlled_core_action = TRUE` when at least one of V2, V3, or V4 is hit. Per-restaurant block in `viability_tests/activation_value_metrics.sql` (driven from clean_base) provides this flag for consolidation.

