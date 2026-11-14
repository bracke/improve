# Dependency compatibility matrix

Validated against the sibling checkouts present on 2026-11-03. Publication additionally requires the constraints in
`alire.release.toml` to resolve without local pins.

### ada_quality 0.1.0, schema 3

Improve uses `Ada_Quality.Reporting`. Read-only snapshots expose registry projects, all run states, immutable
provenance, and exactly 33 typed results.

### database 0.14.0

Typed schemas and transactions support the separate Improve-owned state database; no JSON persistence is needed.

### model_runner_framework 0.1.0 (`^0.1.0` release)

Improve uses `Framework.Tasks` and `Framework.Stores`. Native candidate creation, kind validation, dependency checks,
and crash-recoverable transactions are public.

`model_runner_framework.gpr` exposes the framework independently of the inference engine. Direct linkage is valid,
and its Alire subcrate depends only on `hostkit`. Execution-specific readiness, workspace, and whole-project consistency
checks register with the task/configuration layer when the full harness is linked. Improve compiles the typed
publication closure without selecting `model_runner_main.adb` or inference, transport, repository, and media backends.

One mismatch in the proposed baseline was resolved against the actual Ada Quality contract: a persisted `Failed /`
`Violation` result is not valid in schema 3. `Ada_Quality.Types.Is_Valid` permits failed, blocked, and errored execution
only with unknown compliance and unavailable measurement. Improve therefore creates an investigation candidate for
those valid states; it never assumes a compliance violation that the reporting API cannot return.

