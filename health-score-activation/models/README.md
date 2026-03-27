## `models/` – Core SQL models

This folder mirrors a **dbt-style models layer**. Each `.sql` file should be a self-contained query that can be copy-pasted into Metabase.

### Subfolders

- `staging/` – 1:1, lightly cleaned representations of raw source tables.
  - Naming: `stg_<source>_<entity>.sql` (e.g. `stg_app_users.sql`, `stg_app_events.sql`).
- `intermediate/` – Feature-building and business logic joins.
  - Naming: `int_<domain>_<purpose>.sql` (e.g. `int_activation_events_enriched.sql`).
- `marts/activation/` – Final outputs powering activation health score reporting.
  - Naming: `mart_activation_<output>.sql` (e.g. `mart_activation_health_score.sql`).

### SQL file header convention

Each SQL file should start with a short metadata header:

```sql
-- MODEL: mart_activation_health_score
-- PURPOSE: Final per-user activation health score for Suflex.
-- INPUTS:
--   - int_activation_user_features
-- OWNER: <your-name>
-- VERSION: v001
-- STATUS: draft | candidate | production
```

Use `VERSION` to track logical revisions; older versions can live in `models/intermediate/` until superseded.

