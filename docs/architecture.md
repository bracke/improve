# Architecture

Improve consumes one immutable `Ada_Quality.Reporting.Session`, builds deterministic remediation specifications, and
publishes approved specifications through `Model_Runner.Framework.Tasks.Create` in a harness transaction.

The assessment database is never created, migrated, recovered, or written by Improve. Improve's own state database
is a separate boundary. A model_runner commit and an Improve mapping commit are deliberately treated as two durable
operations joined by a stable origin identifier and recovery, not as a distributed transaction.

The model_runner crate currently exposes its framework packages from the same GPR project as its inference engine.
The publication adapter is consequently isolated. A lightweight public framework library target remains the desired
upstream integration improvement; no framework record or transaction behavior is copied here.

