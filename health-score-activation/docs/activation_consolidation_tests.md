## Activation Consolidation Tests

This file tracks **integration tests** for the Activation Health Score: running each bucket together with the consolidation logic to validate joins, point totals, and activation buckets before going to Metabase.

**Where to run:** DBeaver first (validate SQL and cost); then Metabase (validate execution and dashboards).

**Cohort:** Defined only in consolidation/mart as `base_restaurants` (hygiene + 30-day TTVW). Bucket models return one row per restaurant that has at least one metric in that bucket; consolidation LEFT JOINs them so cohort restaurants with no bucket data get NULL for that bucket’s columns.

**References:**  

- Bucket models: `models/intermediate/activation_bucket_setup.sql`, `activation_bucket_effort.sql`, `activation_bucket_value.sql`.  
- Consolidation: `models/intermediate/activation_health_score_consolidation.sql`.  
- Mart (single execution): `models/marts/activation/mart_activation_health_score.sql`.  
- Metric definitions: `docs/metrics.md`.

---

## Test plan (three combinations)


| Test       | Description            | Status          |
| ---------- | ---------------------- | --------------- |
| **Test 1** | Setup + Consolidation  | **Passed** |
| **Test 2** | Effort + Consolidation | **Passed**      |
| **Test 3** | Value + Consolidation  | **Passed**      |


After all three pass, run the **full mart** (all buckets + consolidation) and confirm cost <500k and correct activation buckets.

---

## Test 1: Setup + Consolidation

**Goal:** Confirm that the Setup bucket output joins correctly to the consolidation, that Setup points (S1, S2, S3) and total_score (Setup-only when Effort/Value are stubbed or empty) and activation_bucket behave as expected.

### SQL to run (DBeaver)

**File:** `consolidation_tests/test1_setup_consolidation.sql`

| Step | What it does | How to compare |
|------|--------------|----------------|
| **1** | Setup points for cohort only. Same cohort as consolidation. Output: `restaurant_id`, `pts_s1_logins`, `pts_s2_lists_with_controlled`, `pts_s3_controlled_with_weight`. | Same column names as Step 2’s Setup columns. |
| **2** | Full consolidation (all buckets). Same cohort; same Setup columns plus Effort, Value, `total_score`, `activation_bucket`. | Run `EXPLAIN`; aim cost &lt;500k. |
| **3** | Comparison: runs Step 1 and Step 2 Setup logic, returns rows where Setup points differ. | **0 rows = pass.** Any row = mismatch (step1_* vs step2_*). |

Run Step 1 and Step 2 to spot-check; run **Step 3** to validate—0 rows means Setup in consolidation matches Setup-only.

### What to check

- **Step 1 vs 2:** Same cohort, same Setup column names; run Step 3 to compare automatically.
- **Step 3:** 0 rows = Setup points match; investigate any returned rows.
- **Step 2:** One row per cohort restaurant; `total_score` 0–100; `activation_bucket` correct; EXPLAIN cost &lt;500k.

### Status and observations

- **Status:** **Passed**
- **Observations:** Step 1, Step 2, and Step 3 all OK. Step 3 returned 0 rows (Setup points match).

---

## Test 2: Effort + Consolidation

**Goal:** Confirm Effort bucket joins correctly to consolidation; E1–E4 points match between Effort-only and full pipeline.

### SQL to run (DBeaver)

**File:** `consolidation_tests/test2_effort_consolidation.sql`

| Step | What it does | How to compare |
|------|--------------|----------------|
| **1** | Effort points for cohort only. Same cohort as consolidation. Output: `restaurant_id`, `pts_e1_50_prints`, `pts_e2_30_controlled_prints`, `pts_e3_10_baixas`, `pts_e4_5_contagens`. | Same column names as Step 2’s Effort columns. |
| **2** | Full consolidation: run `models/marts/activation/mart_activation_health_score.sql` separately. | Run `EXPLAIN`; aim cost &lt;500k. Spot-check Effort cols. |
| **3** | Comparison: runs Step 1 and duplicate Effort logic, returns rows where Effort points differ. | **0 rows = pass.** Any row = mismatch (step1_* vs step2_*). |

Run Step 1, then Step 2 (mart), then Step 3. 0 rows from Step 3 = Effort in consolidation matches Effort-only.

### What to check

- **Step 1 vs 2:** Same cohort, same Effort column names; run Step 3 to compare automatically.
- **Step 3:** 0 rows = Effort points match; investigate any returned rows.
- **Step 2:** One row per cohort restaurant; max Effort = 30 pts; EXPLAIN cost &lt;500k.

### Status and observations

- **Status:** **Passed**
- **Observations:** Step 1, Step 2 (mart), and Step 3 all OK. Step 3 returned 0 rows (Effort points match).

---

## Test 3: Value + Consolidation

**Goal:** Confirm Value bucket joins correctly; V1–V4 points and Key (`has_weighted_controlled_core_action`) match between Value-only and full pipeline.

### SQL to run (DBeaver)

**File:** `consolidation_tests/test3_value_consolidation.sql`

| Step | What it does | How to compare |
|------|--------------|----------------|
| **1** | Value points + Key for cohort only. Same cohort as consolidation. Output: `restaurant_id`, `pts_v1_20_prints_weight`, `pts_v2_30_controlled_weight`, `pts_v3_5_baixas_controlled_weight`, `pts_v4_2_contagens_controlled_weight`, `has_weighted_controlled_core_action`. | Same column names as Step 2’s Value columns + Key. |
| **2** | Full consolidation: run `models/marts/activation/mart_activation_health_score.sql` separately. | Run `EXPLAIN`; aim cost &lt;500k. Spot-check Value cols and Key. |
| **3** | Comparison: runs Step 1 and duplicate Value logic, returns rows where Value points or Key differ. | **0 rows = pass.** Any row = mismatch (step1_* vs step2_*). |

Run Step 1, then Step 2 (mart), then Step 3. 0 rows from Step 3 = Value + Key in consolidation match Value-only.

### What to check

- **Step 1 vs 2:** Same cohort, same Value column names + Key; run Step 3 to compare automatically.
- **Step 3:** 0 rows = Value points and Key match; investigate any returned rows.
- **Step 2:** One row per cohort restaurant; max Value = 60 pts; Key = 1 when V2 or V3 or V4 hit; EXPLAIN cost &lt;500k.

### Status and observations

- **Status:** **Passed**
- **Observations:** Step 1, Step 2 (mart), and Step 3 all OK. Step 3 returned 0 rows (Value points and Key match).

---

## Full mart run (after Tests 1–3)

- **File:** `models/marts/activation/mart_activation_health_score.sql`.  
- **Checks:** One row per cohort restaurant; all point columns and `total_score` (0–100), `activation_bucket` correct; EXPLAIN cost <500k.  
- **Status:** *(To be updated after Tests 1–3 pass.)*

