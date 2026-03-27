## Suflex Activation Health Score Project

This project defines a **dbt-like structure** to design, document, and version the SQL logic for Suflex's activation-focused health score, before implementing the final queries in Metabase.

### Goals

- **Organize SQL logic** (staging, intermediate, marts) so it is easy to reason about.
- **Version and experiment** with different health score definitions and activation logic.
- **Document domain knowledge** (definitions, assumptions, thresholds) alongside the queries.
- **Prepare for Metabase** by keeping all final queries copy-pasteable into Metabase questions or models.

### Folder structure (high level)

- `models/` – Core SQL models, structured like dbt:
  - `staging/` – Clean, 1:1 views of source tables.
  - `intermediate/` – Feature-building models and business logic joins.
  - `marts/activation/` – Final activation health score outputs.
- `viability_tests/` – Queries to validate each metric (EXPLAIN, then run) on the prod snapshot.
- `models/intermediate/` – Iterate on metric queries here until final.
- `docs/` – Concepts, metric definitions, and **references** (SQL query patterns + activation_health_score.yml spec).
- `schema/` – Table DDL from the prod snapshot (DBeaver); source of truth for table/column names.

See `docs/` for concepts, metrics, and reference material.

