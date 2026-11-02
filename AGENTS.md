# Repository Guidelines

This repository is an Ada 2022 command-line remediation planner. Quality evidence is read only through
`Ada_Quality.Reporting`; remediation state belongs to Improve; task execution state belongs to model_runner.

Use Alire GNAT 15 only. Invoke compiler, builder, documentation, and prover commands through `alr exec --`.
The root and test manifests must pin `gnat_native = "=15.2.1"`.

Production units belong in `src/`, tests in `tests/src/`, and architecture/contract material in `docs/`. Use GNAT
naming, three-space indentation, Ada 2022, GNATdoc comments for public APIs, and the 120-column limit. Keep CLI,
terminal, and JSON presentation separate from deterministic domain logic.

Never modify or migrate an Ada Quality database from Improve. Do not duplicate model_runner task records or task
lifecycle logic. Do not shell out to either dependency when a typed API is available. Preserve stable finding
fingerprints and provenance, reject unsafe project-relative paths, and make publication explicit and idempotent.

Preferred validation:

```sh
alr exec -- gnatls --version
alr build
cd tests && alr build && ./bin/improve_tests
```

