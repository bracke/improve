# Integration contracts

## Quality input

Improve uses `Ada_Quality.Reporting.Open`, `Projects`, `Runs`, `Read_Assessment`, `Snapshot_Identity`, and `Close`.
Selection chooses the greatest persisted identity whose state is `Assessment_Completed`. Every loaded assessment must
contain each of the 33 registered indicators exactly once and in registry order.

Improve computes an assessment-specific identity from the complete typed run metadata, indicator results,
measurements, and findings. Planning persists that identity and publication authenticates the exact run against it.
The reporting snapshot identity is retained only as audit provenance because unrelated projects can change the shared
database snapshot without changing the selected assessment.

A persisted project identity includes the canonical Ada Quality database path, numeric registry identity, and
canonical project root. Improve rejects application, refresh, reconciliation, and verification when the selected
database resolves an equal numeric identity to another project. Plans from independent databases remain separate even
when both registries assign the same number.

## Harness output

Improve discovers task kinds and their required/allowed fields from the open project store. It creates tasks with
`Model_Runner.Framework.Tasks.Create` and commits them with `Model_Runner.Framework.Stores.Commit`. Quality indicator
IDs are evidence labels, never fabricated harness requirement IDs.

Before publication, Improve compares the current project source with the planning-time source fingerprint. Generated
build trees, runtime databases, and `.model_runner` state are excluded because task publication changes them itself.
Changes to project source, manifests, documentation, or other authored inputs invalidate publication until the project
is remeasured and replanned.

Before generating a plan, Improve also recomputes `Ada_Quality.Checks.Source_Fingerprint` and requires it to equal the
selected assessment's persisted source identity. This is separate from publication staleness: measurement evidence
cannot be combined with source that changed before planning. Mutable quality and state databases should live outside
the registered project root so their own transactions do not invalidate authoritative source comparison.

## Optional refinement

`Improve.Refinement.Adapter` is the only agent-planning boundary. It receives bounded `Planning_Context` with typed
evidence and task collections, and returns typed proposals under a cooperative deadline. Diagnostic and source text
remain untrusted data. The validator, not the adapter, controls evidence identity, quality policy, paths, dependencies,
task limits, and persistence. The interactive model_runner `/work` workflow is not an automation API and is never
invoked for planning.

