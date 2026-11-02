# Integration contracts

## Quality input

Improve uses `Ada_Quality.Reporting.Open`, `Projects`, `Runs`, `Read_Assessment`, `Snapshot_Identity`, and `Close`.
Selection chooses the greatest persisted identity whose state is `Assessment_Completed`. Every loaded assessment must
contain each of the 33 registered indicators exactly once and in registry order.

## Harness output

Improve discovers task kinds and their required/allowed fields from the open project store. It creates tasks with
`Model_Runner.Framework.Tasks.Create` and commits them with `Model_Runner.Framework.Stores.Commit`. Quality indicator
IDs are evidence labels, never fabricated harness requirement IDs.

