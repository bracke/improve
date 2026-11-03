# Native model runner publication

Selective publication retains the complete immutable plan while creating only the requested task. Dependency lookup
therefore resolves against both the full plan graph and durable publication mappings. A dependency already published
to model_runner is translated to its native task identity. An unpublished prerequisite stops publication with its
exact Improve task identity and instructs the operator to publish that prerequisite first.

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
improve:<project-path-digest>:task:<improve-task-id>:contract:<task-contract-digest>
```

Before staging work, publication scans native task definitions for that exact authenticated provenance and compares the
complete title, kind, priority, acceptance, notes, and native dependency definition. A matching task is adopted, not
recreated. The notes preserve the goal, problem, evidence, relevant files, scope, exclusions, requirements, verification
instructions, and canonical contract digest. This handles the non-atomic boundary where the harness commit succeeded
but recording the mapping in Improve state failed. Improve records the contract-qualified `IMP-` to `TASK-` mapping in
a separate database transaction after the harness commit; conflicting reuse is rejected. A logical Improve task may
continue across revisions, but a changed execution contract receives a distinct native origin and replacement task.
The replacement notes name every earlier native predecessor with a `Supersedes:` relationship.

Replacement is an explicit harness lifecycle operation authorized by the approved `apply`. Candidate predecessors move
to `rejected`; accepted, blocked, and failed predecessors move to `cancelled`; cancelled and rejected predecessors stay
historical; and completed predecessors remain completed. A predecessor in `running` or `verification` blocks automatic
replacement until the operator resolves that active work through the normal harness workflow. Project transition policy
is respected, and an unavailable retirement transition blocks publication.

Recovery first runs an existing-only provenance probe. A completely committed harness transaction is adopted without
replaying creation. If native work is missing, recovery requires durable exact-revision approval and the same current
source fingerprint enforced by normal publication. Failed revalidation leaves the operation journal entry pending.

Normal publication also compares the newest completed assessment policy fingerprint with the immutable plan baseline.
A changed policy requires replanning before any harness transaction is opened, even when source identity is unchanged;
this preserves authored acceptance intent. Toolchain changes are not blanket publication failures and remain subject to
indicator-specific verification comparability.

Tasks are staged in dependency order and `depends_on` contains the assigned native task IDs. Predecessor retirement and
replacement creation use the same harness transaction, which commits only after every selected definition validates. A
dry run performs the same task-kind, lifecycle, and native-definition validation without changing harness state.

The resulting native state is normally `candidate`. If project policy auto-accepts the task kind or Improve origin, the
adapter reports the actual post-commit state and never overrides that policy.

## Reconciliation

`improve refresh` reads each stored native task through the framework, verifies both `created_by=improve` and its exact
origin, and then updates only Improve's cached copy of the harness state. It never moves a harness task. Missing tasks,
changed origins, and mismatched creators are integrity failures rather than mappings that Improve silently adopts.
