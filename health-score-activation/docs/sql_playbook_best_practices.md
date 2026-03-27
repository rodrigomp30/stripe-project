## SQL & Data Engineering Playbook – Production Snapshot & Metabase

This playbook summarizes the core best practices you are using when working with the Suflex production snapshot, especially for the Activation Health Score project.

---

### 1. Handling Messy Data (JSON & Logs)

- **Pre-filter noisy logs ("Noise Canceller")**  
  - Never feed the raw event log table directly into window functions.  
  - First create a filtered layer that keeps only meaningful state changes, e.g.:  
    - `after IN ('true', 'false')`  
    - `before IS DISTINCT FROM after`

- **Extract JSON safely**  
  - Use PostgreSQL `->>` to extract JSON values as text.  
  - Explicitly compare or cast those values (e.g. `field->>'active' = 'true'`) to derive clean boolean flags.

- **Use `COALESCE` on first states**  
  - When building timelines from delta logs, the initial `before` state is often `NULL`.  
  - Wrap it with `COALESCE(..., FALSE)` (or an appropriate default) to avoid propagating `NULL` into your activation logic.

- **Shared products without `owner_id`**  
  - Some products are shared across multiple restaurants (no `owner_id`).  
  - When you need **restaurant-specific behavior** (e.g. `shelflife_categories`, controlled flags, unit heuristics), always:  
    - Join via `restaurant_products` (`products p JOIN restaurant_products rp ON p.id = rp.product_id`).  
    - Include `restaurant_id` in downstream joins (e.g. `rp.restaurant_id = sc.restaurant_id`) so you don’t mix data between restaurants.

- **Impressões (prints): do not use `tags` / `tags_receivings` for restaurant**  
  - `tags.restaurant_id` and `tags_receivings.restaurant_id` are **not reliable**.  
  - Use **`tag_infos`** and **`tag_infos_receivings`** to filter by restaurant (`restaurant_id`).  
  - For quantity of prints, use the **`tags_count`** field (per row), e.g. `SUM(COALESCE(tags_count, 1))` when aggregating.

- **Baixas (etiquetas excluídas / removidas)**  
  - Use **`tags_count_removed`** in **`tag_infos`** and **`tag_infos_receivings`** to count removed (baixadas) tags per restaurant.  
  - Same pattern: filter by `restaurant_id` and time window, then `SUM(COALESCE(tags_count_removed, 0))` per restaurant.

- **Recebimentos (receivings)**  
  - To get **all receivings per restaurant** (with or without printed tags), use **`receivings`** and **`receivings_products`**.  
  - Not used in the current activation health score design; keep for other analyses.

---

### 2. Performance & Cost Optimization (Big Tables)

- **Always push date filters to fact tables**  
  - When joining a small, filtered dimension (e.g. 45 recent accounts) to a huge fact table (tens of millions of rows), always add date predicates directly on the fact table.  
  - Otherwise, the planner may scan the entire fact table before joining.

- **Be careful with CTEs as “optimization fences”**  
  - A nice “Time Window” CTE is good for readability/DRY, but can sometimes prevent the planner from pushing filters down.  
  - If you see `Seq Scan` on a huge table in `EXPLAIN`, consider inlining the date conditions in multiple places so the planner can use indexes.

- **Use `EXPLAIN` vs `EXPLAIN ANALYZE` deliberately**  
  - `EXPLAIN` → see the **plan** (Seq vs Index Scan, estimated cost) without running the query.  
  - `EXPLAIN ANALYZE` → run the query and see **actual** timings and row counts; use this to pinpoint real bottlenecks.

---

### 3. Designing for Analytics & Metabase

- **Shape data for the tool (long vs wide)**  
  - Metabase and other BI tools handle funnels and breakdowns better with **long** data (one row per step per entity) than wide (many step columns on one row).  
  - Use `UNION ALL` to pivot multiple step metrics into a `(step_name, value)` structure when building funnels.

- **Strict subset logic for funnels**  
  - Each funnel step must be a strict subset of the previous step’s audience.  
  - Example: someone cannot be in “finished count” if they were never in “started count”; enforce this by joining/filtering on prior-step cohorts.

- **Boolean aggregation with `MAX` (“Has Any” trick)**  
  - When collapsing multiple rows per user into one, use:  
    - `MAX(CASE WHEN <condition> THEN 1 ELSE 0 END) AS has_event`  
  - This strictly answers “Did this happen at least once?” and avoids overcounting that `SUM` could introduce.

---

### 4. Debugging & Development Workflow

- **Isolation testing on known entities**  
  - When a 100‑line query is wrong, don’t debug it as a monolith.  
  - Pick a single, known account/user, and:  
    - Strip the query down to its core CTEs.  
    - Validate each layer step by step (raw → filtered logs → features → scores).

- **Iterate in DBeaver, promote to Metabase**  
  - Use DBeaver on the production snapshot for fast iteration and inspection (including `EXPLAIN`/`EXPLAIN ANALYZE`).  
  - Once a query is correct and performant, copy it into the corresponding file in `models/` and then into Metabase as a model or question.

---

You can keep extending this playbook with concrete examples from the Activation Health Score models (e.g. how you apply date windows, JSON extraction, and “Has Any” flags for key activation behaviors).

