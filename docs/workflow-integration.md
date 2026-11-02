# Native model runner publication

`Improve.Workflow` publishes only through `Model_Runner.Framework.Tasks.Create` and one
`Model_Runner.Framework.Stores.Transaction`. Improve does not write harness record files, infer task states, accept
candidates, or introduce an execution command.

## Compatibility and mapping

The adapter opens the initialized project named by the stored project reference and reads its resolved task kinds. An
explicit `workflow.task_kind` must exist. `auto` succeeds only when exactly one task kind exists; ambiguous projects are
rejected without a commit.

Improve maps title, selected kind, numeric priority, acceptance, translated dependencies, and bounded background notes
to core harness fields. Ada Quality indicator IDs remain evidence in notes and are never inserted as requirement IDs.
Any project-required field that cannot be supplied is rejected by the harness before the transaction commits.

Priority mapping is deterministic: critical 100, high 75, normal 50, and low 25. The harness remains authoritative for
field schemas, component inference, task identifiers, auto-accept policy, lifecycle state, and readiness.

## Provenance and recovery

Every task is created with `created_by=improve` and an origin of the form:

```text
improve:<plan-fingerprint>:<improve-task-id>
```

Before staging work, publication scans native task definitions for that exact authenticated provenance. A task found
there is adopted, not recreated. This handles the non-atomic boundary where the harness commit succeeded but recording
the mapping in Improve state failed. Improve records the verified `IMP-` to `TASK-` mapping in a separate database
transaction after the harness commit; conflicting reuse is rejected.

Tasks are staged in dependency order and `depends_on` contains the assigned native task IDs. The harness transaction is
committed only after every selected definition validates. A dry run performs the same task-kind and native-definition
validation in an uncommitted transaction opened on read-only harness state.

The resulting native state is normally `candidate`. If project policy auto-accepts the task kind or Improve origin, the
adapter reports the actual post-commit state and never overrides that policy.

## Reconciliation

`improve refresh` reads each stored native task through the framework, verifies both `created_by=improve` and its exact
origin, and then updates only Improve's cached copy of the harness state. It never moves a harness task. Missing tasks,
changed origins, and mismatched creators are integrity failures rather than mappings that Improve silently adopts.
