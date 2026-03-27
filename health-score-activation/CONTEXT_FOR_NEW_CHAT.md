# Context for new chat – Activation Health Score

Copy the section below into a **new chat** and attach only the files you’re working on (use @ to reference them). This keeps the AI focused on the active code.

---

## Project summary

**Goal:** Build activation health score (0–100 pts) for Suflex. Queries run in DBeaver on prod snapshot, then go to Metabase. No warehouse; no direct DB writes.

**Scoring:** Setup 10 pts (S1 logins, S2 listas+controlados, S3 controlados com peso) | Effort 30 pts (E1 50 impressões, E2 30 controladas, E3 10 baixas, E4 5 contagens) | Value 60 pts (V1–V4 weighted prints/baixas/contagens). Lock ≥80 pts + Key (≥1 value action with weight: V2, V3, or V4). Buckets: `green_activated` / `orange_false_positive` / `yellow_at_risk` / `red_failure`.

**Rules (in docs):** Use `tag_infos` + `tag_infos_receivings` and `tags_count` (not `tags`); baixas = `tags_count_removed`; shared products → `restaurant_products` + `restaurant_id`. Roles: `restaurant_admin` = gestor, `restaurant_employee` = colaborador. **S1 in Metabase:** gestor + colaborador logins split; Metabase “total” can differ from canonical mart if only one role logged in.

**Cost:** Keep query cost &lt;500k (aim 200k–300k). Drive from `qualified_base` (or `clean_base`) and join to big tables on `restaurant_id` + date so the planner uses indexes.

---

## Current state

- **Viability:** All metrics tested (OK). `viability_tests/activation_setup_metrics.sql`, `activation_effort_metrics.sql`, `activation_value_metrics.sql`. Per-metric status in `docs/metrics.md`.

- **Models (dbt-style):**
  - **Cohort** lives only in consolidation + mart: `base_restaurants` (hygiene + 30-day TTVW).
  - **Bucket models** (one row per restaurant with at least one metric in that bucket): `models/intermediate/activation_bucket_setup.sql`, `activation_bucket_effort.sql`, `activation_bucket_value.sql`.
  - **Consolidation** (full inline logic): `models/intermediate/activation_health_score_consolidation.sql`.
  - **Mart** (same logic, single execution for Metabase): `models/marts/activation/mart_activation_health_score.sql`.

- **Metabase (native SQL, paste whole file):** One **summary** + one **metrics** file. Cohort matches the mart: hygiene + `restaurants.inserted_at` in the last 30 days (TTVW). Activity metrics use rolling last 30 days.
  - **Summary:** `mart_activation_health_score_metabase.sql` — trading name, restaurant ID, dias desde cadastro, bucket label, bucket flag (1–4), total score, Key / Lock / Ativado.
  - **Detail:** `mart_activation_health_score_metabase_metrics.sql` — 12 metric ✅/❌ + trading name + ID; **field filter** `nome_do_restaurante` on `restaurants.trading_name` via `AND (1=0 [[ OR (1=1 AND {{nome_do_restaurante}}) ]])`. If the optional `OR` block is omitted, `1=0` returns no rows.
  - **Style:** Physical tables use full names (`restaurants`, `tag_infos`, …); CTEs keep short names (`clean_base`, `s1`, `final`, …). Notes in `models/marts/activation/README.md`.

- **Consolidation tests (DBeaver):** `docs/activation_consolidation_tests.md`. Tests 1 (Setup), 2 (Effort), and 3 (Value) are **passed**. Test SQL: `consolidation_tests/test1_setup_consolidation.sql`, `test2_effort_consolidation.sql`, `test3_value_consolidation.sql`. Step 3 comparison queries use `MATERIALIZED` CTEs (PostgreSQL 12+).

- **Manual validation (per-restaurant source rows):** `tests/manual_validation/single_restaurant_source_records.sql` — E2 uses `LEFT JOIN controlled_products`; V2/V3 use **`JOIN controlled_products`** for `controlled_product_id`.

- **Legacy:** `models/intermediate/activation_health_score_consolidation_template.sql` — superseded by `activation_health_score_consolidation.sql`; keep only for historical reference.

- **Next (optional):** Full mart EXPLAIN + spot-checks; dashboards / CS views; golden-restaurant checks.

---

## Which files to @ in the new chat

**Mart / Metabase / small changes:**
- `models/marts/activation/mart_activation_health_score.sql`
- `models/marts/activation/mart_activation_health_score_metabase.sql`
- `models/marts/activation/mart_activation_health_score_metabase_metrics.sql`
- `models/intermediate/activation_health_score_consolidation.sql`
- `docs/metrics.md`
- `docs/activation_consolidation_tests.md`

**Manual validation / edge cases:**
- `tests/manual_validation/single_restaurant_source_records.sql`

**Bucket or viability deep-dives:**
- `models/intermediate/activation_bucket_setup.sql` (or `_effort`, `_value`)
- `viability_tests/activation_setup_metrics.sql` (or `_effort`, `_value`)

**Reference:**
- `docs/references/activation_health_score.yml`
- `docs/sql_playbook_best_practices.md`

---

**Example first message in new chat:**

“Continuing the Activation Health Score project. Summary is in CONTEXT_FOR_NEW_CHAT.md. I’m adjusting the Metabase metrics question / mart filter. @models/marts/activation/mart_activation_health_score_metabase_metrics.sql @docs/metrics.md”
