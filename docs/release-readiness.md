# Release readiness

Phase 9 consolidates every implementation phase into one executable release gate. The gate and its supporting
repository checker and coverage driver are Ada 2022 programs:

- `tools/src/check_phase_9.adb` orchestrates the complete gate;
- `tools/src/check_release_candidate.adb` validates a clean, pin-free staged release with Ada Quality;
- `tools/src/check_all.adb` enforces repository, Ada-only tooling, formatting, and structural unit-size policy;
- `tools/src/improve_coverage.adb` builds instrumented binaries, runs them, parses gcov evidence, and applies the
  production threshold.

CI additionally runs the optional runtime on Linux and Intel macOS, exercises real host SIGINT delivery, and runs a
scheduled digest-pinned production-GGUF CLI round trip with wall-time, peak-memory, and stored-provenance checks.
Windows is explicitly unavailable while pinned dependencies require POSIX process, locking, and durability APIs. A
fast dependency/import preflight gates expensive jobs, while a cache-free job builds every development manifest and
project root. OS-scoped caches shorten other builds; job timeouts, concurrency cancellation, and uploaded diagnostics
bound and explain failures. Release-gate jobs install pinned `gnatdoc_bin=26.0.0` and `gnatprove=15.1.0` Alire
binaries instead of depending on runner-global tools. The repository checker validates the exact dependency lock
against every workspace pin. Diagnostic logs are written outside the checkout so observation cannot change the source
fingerprint under assessment.

Build and run the gate from the repository root:

```text
alr build --validation --stop-after=generation
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
2. All 134 AUnit cases pass, including schema, structured-error, audit, inference-client, property, and scale coverage.
3. Repository structure, 120-column Ada source policy, required release files, and the Ada-only tooling rule pass.
4. GNATdoc accepts every Improve package without warnings while excluding dependency-owned APIs.
5. GNATprove proves every source unit that declares `SPARK_Mode` at level 2; the repository check rejects an omitted
   SPARK unit.
6. Instrumented AUnit and CLI executions cover at least 90% of executable production lines and write fingerprinted
   evidence for Ada Quality.
7. Version, license, release dependency, pin, and dependency-license records are internally consistent.
8. The versioned JSON Schema, generated completions, roff man page, and release automation workflow are present.

The coverage driver inventories production units through Ada Quality, requires gcov records for every unit, and rejects
missing objects. The only zero-line exception is the explicitly reviewed empty `Improve.Operations` namespace; future
spec-only units fail closed. Test sources are never counted as production. The generated result and fingerprints are
recorded in `coverage/gcov-summary.txt`.

## Publication dependency gate

`alire.release.toml` is the authoritative pin-free publication manifest. The development manifest remains pinned to
sibling checkouts so integration work is reproducible. The clean release gate must resolve every constrained release
from the configured Alire indexes; local sibling directories are intentionally unavailable to that resolution.

At the time the `0.1.0` candidate was prepared, the required internal crates were not present in the configured Alire
index. This is an external publication prerequisite, not a bypassable check: publish compatible releases of those
crates first, then rerun `tools/bin/check_release_candidate` and review the selected dependency solution.

The optional `model_runner_runtime` directory is an independent crate with development and pin-free release
manifests. The clean release checker stages that release manifest, resolves `improve ^0.1.0` and
`model_runner ^0.1.0`, and Phase 9 builds its CLI and compatibility tests from the runtime crate environment.

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
