## `models/staging/` – Source-level models

Use this folder for **1:1 cleaned views** of your raw SaaS data sources (the equivalent of dbt staging models).

### Purpose

- Standardize column names and data types.
- Apply minimal cleaning (e.g. trim strings, parse timestamps, handle obvious nulls).
- Keep logic here **close to the raw tables**; defer business rules to `intermediate/`.

### Example files

- `stg_app_users.sql` – cleans `raw.app_users` (or equivalent).
- `stg_app_events.sql` – cleans `raw.app_events` (or equivalent).
- `stg_subscriptions.sql` – cleans billing/subscription data.

Each file should follow the header convention described in `models/README.md`.

