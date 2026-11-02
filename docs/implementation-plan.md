# Implementation plan

1. Prove the read-only reporting and native task-transaction contracts against local dependency versions.
2. Establish the strict CLI, configuration, presentation, test crate, and release checks.
3. Ingest and validate all 33 typed indicator results and normalize stable finding identities.
4. Register all indicator strategies and produce deterministic, bounded, acyclic task proposals.
5. Persist immutable plan revisions and operation journal records in the Improve-owned database.
6. Publish through model_runner task-kind validation and transactions with origin-based recovery.
7. Reconcile task state separately from quality verification and detect regressions.
8. Add optional, validated agent refinement without weakening deterministic behavior.
9. Complete terminal/JSON schemas, operational recovery, security limits, and end-to-end release gates.

Every phase must leave the crate compiling and its tests passing. Later phases may extend stored schemas and command
behavior but must not weaken the ownership boundaries established in the earlier phases.

The executable Phase 6 gate is `tools/check_phase_6.sh`. It performs the warning-clean validation build, runs the full
AUnit suite (including harness-state reconciliation and resolved, partial, still-failing, unavailable-evidence,
regression, incomparable-policy, and incomplete-assessment verification scenarios), builds the repository checker, and
runs it. CI invokes this same entry point.
