# Viability tests

Queries used to **validate** that each activation metric can be computed efficiently on the production snapshot (DBeaver → EXPLAIN, then run).

- Run with `EXPLAIN` first to check cost and index usage.
- When a query is stable and performant, copy it into `models/intermediate/` and iterate there until you have the final version for each metric.
