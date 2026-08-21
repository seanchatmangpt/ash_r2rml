# Legacy path: atomics

AshR2ML does not implement an `Ash.DataLayer` and therefore does not implement its own atomic-write execution path.

Ash atomics, bulk writes, transactions, optimistic locking, and mutation semantics belong to Ash and the active data layer.

See [Actions and mutations](actions.md) for the AshR2ML boundary.

This file remains only so existing `usage_rules` links from the AshNeo4j donor history do not resolve to stale Cypher guidance.
