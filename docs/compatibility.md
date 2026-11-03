# Dependency compatibility matrix

Validated against the sibling checkouts present on 2026-11-03. Publication additionally requires the constraints in
`alire.release.toml` to resolve without local pins.

| Dependency | Version | Contract used | Phase 0 conclusion |
|---|---:|---|---|
| ada_quality | 0.1.0, schema 3 | `Ada_Quality.Reporting` | Read-only snapshots expose registry projects, all run states, immutable provenance, and exactly 33 typed results. |
| database | 0.14.0 | typed schemas and transactions | Suitable for the separate Improve-owned state database; no JSON persistence is needed. |
| model_runner | 0.1.0-dev (`^0.1.0` release) | `Framework.Tasks` and `Framework.Stores` | Native candidate creation, kind validation, dependency checks, and crash-recoverable transactions are public. |

`model_runner.gpr` currently places the framework and inference engine in one source project. Direct linkage is valid,
but it pulls the inference dependency graph into every consumer build. Improve isolates that linkage in its publication
adapter. A separate public framework library target remains the preferred upstream improvement.

One mismatch in the proposed baseline was resolved against the actual Ada Quality contract: a persisted `Failed /`
`Violation` result is not valid in schema 3. `Ada_Quality.Types.Is_Valid` permits failed, blocked, and errored execution
only with unknown compliance and unavailable measurement. Improve therefore creates an investigation candidate for
those valid states; it never assumes a compliance violation that the reporting API cannot return.

