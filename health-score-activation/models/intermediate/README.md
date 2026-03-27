## `models/intermediate/` – Feature and iteration layer

**Dual purpose:**

1. **Iteration** – Refine metric queries here (copy from `viability_tests/` when a query is approved) until you have the final version, then promote to `marts/activation/` or Metabase.
2. **Reference** – Reusable patterns in `docs/references/counting_feature_metrics_reference.sql` for clean_base, enable_feature, inventory/count logic.

Keep feature-building and business logic here so that `marts/activation/` stays thin.

