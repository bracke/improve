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

Every phase must leave the crate compiling and its tests passing. A phase is committed only after its gate succeeds.
Later phases may extend stored schemas and command behavior but must not weaken the ownership boundaries established in
the earlier phases.

Phase 9 is the consolidated release gate. Its Ada entry point is `tools/bin/check_phase_9`, built from
`tools/src/check_phase_9.adb` through `tools/improve_tools.gpr`. It retains every earlier test and adds a real
Ada Quality assessment-to-plan-to-model_runner-to-remeasurement workflow, stable task identity across plan revisions,
configuration and operational CLI paths, documentation generation, SPARK proof, and measured production coverage.

The gate is deliberately not a shell script. All repository check and coverage orchestration lives in Ada and invokes
tools with explicit argument vectors. CI and `alr test` build and invoke this same entry point. See
`docs/release-readiness.md` for the exact checks and current evidence.

Publication adds a final clean-source gate, `tools/bin/check_release_candidate`. It activates the pin-free release
manifests in a temporary source tree, performs fresh builds and coverage, and requires all 33 native Ada Quality
results to pass or be validly not applicable. A missing indexed dependency release blocks publication rather than
silently falling back to a workspace pin.
