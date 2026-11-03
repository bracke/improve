# CLI reference

```text
improve <command> [options]
```

Commands are `projects`, `findings`, `plan`, `apply`, `tasks`, `status`, `refresh`, `verify`, `recover`, `config`,
`help`, and `version`. Global options may precede or follow the command. Unknown, repeated, missing, malformed, and
command-incompatible options are rejected deterministically with exit code 2.

`--format json` writes exactly one versioned JSON document to standard output and disables ANSI styling regardless
of `--color`. Diagnostics are written only to standard error. Inspection commands return zero when inspection
succeeds even when quality findings exist; verification returns one when its requested criteria remain unresolved.

Exit codes are 0 for success, 1 for a completed negative verification, 2 for invalid input, 3 for unavailable
evidence or project state, and 4 for storage, integrity, publication, or internal failure.

## Planning and approval

`improve plan --project PROJECT` stores an immutable plan revision. `improve plan show PLAN-ID` inspects the latest
revision and `improve plan list --project PROJECT` lists stable plan identities. When planning policy requires review,
`improve plan approve PLAN-ID` records approval for the exact current revision and fingerprint. Approval is idempotent
and never transfers to a newer revision.

Historical plan and task state remains directly addressable. `plan show PLAN-ID --revision N` inspects an exact
revision; `tasks --task IMP-ID --revision N` and `verify --task IMP-ID --revision N --run RUN` resolve the task through
the persistent cross-revision index rather than substituting the plan's latest revision. Omitting `--revision` selects
the newest revision that actually contains that logical task.

`verify --project PROJECT --revision N --run RUN` evaluates an exact historical plan revision. Task, plan, and project
evidence records retain that revision and its immutable acceptance-contract fingerprint, so valid evaluations of two
revisions against the same assessment coexist while repeated evaluation of either exact revision remains idempotent.

`improve apply PLAN-ID` rejects an unapproved revision before opening or modifying harness state. `--dry-run` remains
available for publication preflight without approval because it cannot create tasks or publication journal records.
`improve apply PLAN-ID --task IMP-ID` publishes only that task. Its prerequisites are resolved from existing native
publication mappings; an unpublished prerequisite is reported explicitly and is never silently omitted.

## Operational inspection

`improve tasks --project PROJECT` lists every stored Improve task for the selected registered project. `--task ID`
selects one task without requiring the Ada Quality registry, and `--status STATUS` filters the result. Supported
statuses are `proposed`, `published`, `in_progress`, `awaiting_verification`, `verified`, `blocked`, `failed`,
`cancelled`, `rejected`, `partially_resolved`, `still_failing`, `inconclusive`, `regressed`, and `superseded`.
Results have stable task-ID ordering and include the mapped harness task identity when publication has occurred.
The task view retains quality outcome separately from harness runtime state. A quality-resolved task is reported as
`verified` only after the harness work reaches `verification` or `complete`; resolution evidence alone cannot imply
that authored investigation or implementation work was completed.

`verify --task IMP-ID` records task-scoped quality only. `verify --project PROJECT` evaluates every task in the selected
plan and persists separate plan and project assessment outcomes. Status displays unverified aggregate quality until a
complete evaluation exists; it never promotes one successful task to a project-wide conclusion.

`improve status --project PROJECT` summarizes stored plans, task states, and the latest plan's finding outcomes against
the newest completed assessment. `improve status --all` produces the same deterministic summary for every registered
project. A newer failed or incomplete assessment does not replace the most recent completed run.

Plan and project quality are current only when their verification assessment is that newest completed run. Otherwise
terminal output reports `unverified`, the last verification assessment, and its previous historical result. JSON adds
`plan_verification_run`, `plan_verification_current`, `previous_plan_quality`, and equivalent project fields. This
freshness decision is made independently for every project in `status --all`.

Both queries are bounded by `output.maximum_output_items`. They open Improve state read-only and never initialize,
migrate, or repair it.

## Recovery

`improve recover` resumes publication operations that committed model_runner tasks but did not finish recording their
Improve mappings. Recovery verifies each stable Improve origin through the normal native publication adapter, adopts
the existing harness tasks, records their mappings, and completes the journal entry. Repeating recovery is idempotent.
If any native task is missing, recovery revalidates exact-revision approval and current source before creating it. A
stale operation remains pending and creates no work; already committed tasks may still be safely adopted after source
changes because no obsolete task definition is newly published.
The command does not create a missing state database and processes at most
`operations.maximum_recovery_operations` pending entries per invocation.

