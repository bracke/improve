# Architecture

Improve consumes one immutable `Ada_Quality.Reporting.Session`, builds deterministic remediation specifications, and
publishes approved specifications through `Model_Runner.Framework.Tasks.Create` in a harness transaction.

The assessment database is never created, migrated, recovered, or written by Improve. Improve's own state database
is a separate boundary. A model_runner commit and an Improve mapping commit are deliberately treated as two durable
operations joined by a stable origin identifier and recovery, not as a distributed transaction.

Plan generation requires the current authoritative Ada Quality source fingerprint to match the selected completed
assessment. Publication applies a second, harness-state-aware fingerprint to detect authored changes after planning
without treating model_runner's own operational state as a source edit.

The model_runner crate currently exposes its framework packages from the same GPR project as its inference engine.
The publication adapter is consequently isolated. A lightweight public framework library target remains the desired
upstream integration improvement; no framework record or transaction behavior is copied here.

Optional planning assistance sits behind `Improve.Refinement.Adapter`. The adapter receives bounded immutable context
and returns typed proposals; it owns no plan, quality, project, or harness state. Improve validates and fingerprints the
result before normal persistence. model_runner's interactive `/work` path remains exclusively the execution workflow.

Improve is distributed as a CLI executable, not as an Alire library crate. Its supported external interface is the CLI
and its versioned JSON documents. The root `Improve` unit provides shared versioning and deterministic identity support;
child package specifications are implementation contracts used by the executable and tests, not a compatibility-stable
third-party Ada API. GNATdoc therefore audits the root unit, while the complete CLI and JSON contracts are maintained in
`docs/cli-reference.md` and exercised by golden and schema-oriented tests.

