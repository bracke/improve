# Architecture

Improve consumes one immutable `Ada_Quality.Reporting.Session`, builds deterministic remediation specifications, and
publishes approved specifications through `Model_Runner.Framework.Tasks.Create` in a harness transaction.

The assessment database is never created, migrated, recovered, or written by Improve. Improve's own state database
is a separate boundary. A model_runner commit and an Improve mapping commit are deliberately treated as two durable
operations joined by a stable origin identifier and recovery, not as a distributed transaction.

Plan generation requires the current authoritative Ada Quality source fingerprint to match the selected completed
assessment. Publication applies a second, harness-state-aware fingerprint to detect authored changes after planning
without treating model_runner's own operational state as a source edit.

The model_runner repository exposes its framework packages through the lightweight `model_runner_framework` crate.
The publication adapter therefore imports a project with no executable or main-unit target. Execution-specific task
eligibility, workspace, and full consistency checks are registered by the full harness when linked, leaving publication
consumers with the typed task and transaction closure. No framework record or transaction behavior is copied here.

Optional planning assistance sits behind `Improve.Refinement.Adapter`. The adapter receives bounded immutable context
and returns typed proposals; it owns no plan, quality, project, or harness state. Improve validates and fingerprints the
result before normal persistence. model_runner's interactive `/work` path remains exclusively the execution workflow.

Improve is distributed as a CLI executable, not as an Alire library crate. Its supported external interface is the CLI
and its versioned JSON documents. The root `Improve` unit provides shared versioning and deterministic identity support;
child package specifications are implementation contracts used by the executable and tests, not a compatibility-stable
third-party Ada API. GNATdoc therefore audits the root unit, while the complete CLI and JSON contracts are maintained in
`docs/cli-reference.md` and exercised by golden and schema-oriented tests.

