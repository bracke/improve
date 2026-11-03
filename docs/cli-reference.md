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

`improve apply PLAN-ID` rejects an unapproved revision before opening or modifying harness state. `--dry-run` remains
available for publication preflight without approval because it cannot create tasks or publication journal records.

## Operational inspection

`improve tasks --project PROJECT` lists every stored Improve task for the selected registered project. `--task ID`
selects one task without requiring the Ada Quality registry, and `--status STATUS` filters the result. Supported
statuses are `proposed`, `published`, `in_progress`, `awaiting_verification`, `verified`, `blocked`, `failed`,
`cancelled`, `rejected`, `partially_resolved`, `still_failing`, `inconclusive`, `regressed`, and `superseded`.
Results have stable task-ID ordering and include the mapped harness task identity when publication has occurred.

`improve status --project PROJECT` summarizes stored plans, task states, and the latest plan's finding outcomes against
the newest completed assessment. `improve status --all` produces the same deterministic summary for every registered
project. A newer failed or incomplete assessment does not replace the most recent completed run.

Both queries are bounded by `output.maximum_output_items`. They open Improve state read-only and never initialize,
migrate, or repair it.

## Recovery

`improve recover` resumes publication operations that committed model_runner tasks but did not finish recording their
Improve mappings. Recovery verifies each stable Improve origin through the normal native publication adapter, adopts
the existing harness tasks, records their mappings, and completes the journal entry. Repeating recovery is idempotent.
The command does not create a missing state database and processes at most
`operations.maximum_recovery_operations` pending entries per invocation.

