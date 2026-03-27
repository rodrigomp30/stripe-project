## `models/marts/activation/` – Final activation outputs

This folder contains **final, presentation-ready models** for activation and the health score. These are the queries you will ultimately implement in Metabase.

### Example files

- `mart_activation_health_score.sql` – primary per-restaurant activation health score (technical column names).
- `mart_activation_health_score_metabase.sql` – Metabase **summary** (trading name, restaurant ID, dias desde cadastro, bucket label, bucket flag 1–4, total score, Key / Lock / Ativado); 30-day signup cohort + rolling 30-day activity (same idea as mart).
- `mart_activation_health_score_metabase_metrics.sql` – Metabase **detail** (Setup / Effort / Value ✅❌ columns); field filter `nome_do_restaurante` on `restaurants.trading_name`; pair with the summary question.
- `mart_activation_health_score_account.sql` – account-level rollups (if needed).
- `mart_activation_funnel_summary.sql` – activation funnel metrics (e.g. invited → onboarded → activated).

Each model should:

- Use **only staging and intermediate models** as inputs.
- Implement **no raw-source logic** (keep that upstream).
- Be optimized for **Metabase usage** (limited parameters, clear column names, and clear grain).

