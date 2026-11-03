# Integration contracts

## Quality input

Improve uses `Ada_Quality.Reporting.Open`, `Projects`, `Runs`, `Read_Assessment`, `Snapshot_Identity`, and `Close`.
Selection chooses the greatest persisted identity whose state is `Assessment_Completed`. Every loaded assessment must
contain each of the 33 registered indicators exactly once and in registry order.

## Harness output

Improve discovers task kinds and their required/allowed fields from the open project store. It creates tasks with
`Model_Runner.Framework.Tasks.Create` and commits them with `Model_Runner.Framework.Stores.Commit`. Quality indicator
IDs are evidence labels, never fabricated harness requirement IDs.

Before publication, Improve compares the current project source with the planning-time source fingerprint. Generated
build trees, runtime databases, and `.model_runner` state are excluded because task publication changes them itself.
Changes to project source, manifests, documentation, or other authored inputs invalidate publication until the project
is remeasured and replanned.

## Optional refinement

`Improve.Refinement.Adapter` is the only agent-planning boundary. It receives bounded `Planning_Context` and returns
typed proposals under a deadline. The validator, not the adapter, controls evidence identity, quality policy, paths,
dependencies, task limits, and persistence. The interactive model_runner `/work` workflow is not an automation API and
is never invoked for planning.

