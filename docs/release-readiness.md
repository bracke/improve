# Release readiness

Phase 9 consolidates every implementation phase into one executable release gate. The gate and its supporting
repository checker and coverage driver are Ada 2022 programs:

- `tools/src/check_phase_9.adb` orchestrates the complete gate;
- `tools/src/check_release_candidate.adb` validates a clean, pin-free staged release with Ada Quality;
- `tools/src/check_all.adb` enforces repository and Ada-only tooling policy;
- `tools/src/improve_coverage.adb` builds instrumented binaries, runs them, parses gcov evidence, and applies the
  production threshold.

Build and run the gate from the repository root:

```text
alr exec -- gprbuild -P tools/improve_tools.gpr -p -j1
tools/bin/check_phase_9
```

`alr test` and CI invoke the same Ada entry point.

After the candidate is committed, run `tools/bin/check_release_candidate`. This second gate first requires a clean Git
worktree, copies only release source to a temporary directory, activates the pin-free root and test manifests, performs
fresh validation builds, regenerates coverage evidence, and runs a complete 33-indicator Ada Quality assessment. The
temporary tree is removed after success or failure.

## Gate contents

The gate requires all of the following:

1. The application and test crate build in validation mode with warnings treated as errors.
2. All 70 AUnit cases pass.
3. Repository structure, 120-column Ada source policy, required release files, and the Ada-only tooling rule pass.
4. GNATdoc accepts every Improve package without warnings while excluding dependency-owned APIs.
5. GNATprove proves every source unit that declares `SPARK_Mode` at level 2; the repository check rejects an omitted
   SPARK unit.
6. Instrumented AUnit and CLI executions cover at least 90% of executable production lines and write fingerprinted
   evidence for Ada Quality.
7. Version, license, release dependency, pin, and dependency-license records are internally consistent.

The coverage driver inventories production units through Ada Quality, requires gcov records for every unit, and rejects
missing objects. It does not hide uncovered packages or count test sources as production. The Phase 9 implementation
measures 2,864 of 3,177 production lines, or 90.14%.

## Publication dependency gate

`alire.release.toml` is the authoritative pin-free publication manifest. The development manifest remains pinned to
sibling checkouts so integration work is reproducible. The clean release gate must resolve every constrained release
from the configured Alire indexes; local sibling directories are intentionally unavailable to that resolution.

At the time the `0.1.0` candidate was prepared, the required internal crates were not present in the configured Alire
index. This is an external publication prerequisite, not a bypassable check: publish compatible releases of those
crates first, then rerun `tools/bin/check_release_candidate` and review the selected dependency solution.

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
