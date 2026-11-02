# Release readiness

Phase 9 consolidates every implementation phase into one executable release gate. The gate and its supporting
repository checker and coverage driver are Ada 2022 programs:

- `tools/src/check_phase_9.adb` orchestrates the complete gate;
- `tools/src/check_all.adb` enforces repository and Ada-only tooling policy;
- `tools/src/improve_coverage.adb` builds instrumented binaries, runs them, parses gcov evidence, and applies the
  production threshold.

Build and run the gate from the repository root:

```text
alr exec -- gprbuild -P tools/improve_tools.gpr -p -j1
tools/bin/check_phase_9
```

`alr test` and CI invoke the same Ada entry point.

## Gate contents

The gate requires all of the following:

1. The application and test crate build in validation mode with warnings treated as errors.
2. All 58 AUnit cases pass.
3. Repository structure, 120-column Ada source policy, required release files, and the Ada-only tooling rule pass.
4. GNATdoc accepts the focused public root API without warnings.
5. GNATprove proves the SPARK-enabled stable digest root package at level 2.
6. Instrumented AUnit and CLI executions cover at least 90% of executable production lines.

The coverage driver inventories production units through Ada Quality, requires gcov records for every unit, and rejects
missing objects. It does not hide uncovered packages or count test sources as production. The Phase 9 implementation
measures 2,864 of 3,177 production lines, or 90.14%.

## Real integration scenario

`IMP_REAL_END_TO_END_WORKFLOW` creates a real Ada/Alire project fixture and uses the production integration APIs. It:

1. registers the fixture in an Ada Quality database;
2. runs and publishes a real `Ada_Quality.Checks.Assess` result;
3. creates and persists a deterministic Improve plan;
4. initializes real model_runner project state and publishes native candidate tasks;
5. accepts a task and confirms model_runner exposes it as runnable work;
6. applies a controlled source correction and publishes a second real assessment;
7. independently verifies the remediation from the new evidence;
8. creates the next immutable plan revision while preserving unaffected logical task identities; and
9. repeats publication and confirms no duplicate native tasks are created.

Only agent-response and failure-injection paths use controlled substitutes. The primary measurement, persistence,
publication, task-state, remeasurement, and verification sequence uses the real typed libraries.
