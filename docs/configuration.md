# Configuration

`config/improve.toml` is schema version 2. Every value is type- and range-checked. Schema version 1 remains readable;
the version-2 evidence and source-limit settings use documented defaults when absent. Planning task and per-task finding
limits are positive and bounded at 10,000. The only supported initial evidence selection is `latest_completed`, and
publication is always `candidate`; project harness policy may independently auto-accept a published origin or kind.
Settings are section-qualified. Unknown sections, misplaced or duplicate keys, and files larger than 1 MiB are
rejected.

Use `--config PATH` to select a file explicitly. Otherwise Improve discovers only `config/improve.toml` below the
current working directory; it never searches a parent directory or silently treats an unrelated parent configuration
as its own. `config validate` fails when no configuration file is selected or discovered. Commands other than
validation may use built-in defaults when no file is present.

The reporting snapshot is bounded before it is loaded by `quality.maximum_database_projects`,
`quality.maximum_database_runs`, and `quality.maximum_database_findings`. Their defaults are 10,000,
1,000,000, and 2,000,000 respectively.

Complete assessment identity is bounded by `quality.maximum_assessment_bytes`; normalized remediation evidence has a
separate `quality.maximum_normalized_finding_bytes` budget. Both default to 16 MiB and accept at most 256 MiB. The
quality database is rejected before loading when it exceeds `quality.maximum_database_bytes` (1 GiB by default,
2,000,000,000 bytes maximum). `quality.maximum_assessment_findings` defaults to 10,000 and accepts at most 1,000,000.

Working-source identity is bounded by `quality.maximum_source_file_bytes` per file and
`quality.maximum_source_total_bytes` per project. They default to 16 MiB and 256 MiB. The per-file value must not
exceed the total. These validated limits are shared by planning, publication, recovery, and inspection through one
typed evidence-limit contract.

Optional refinement is bounded by `planning.agent_max_context_bytes`, `agent_max_file_bytes`,
`agent_max_response_bytes`, and `agent_timeout_seconds`. Defaults are 131072, 32768, 131072, and 60 respectively.
Context is at least 1024 bytes and at most 10 MiB, a file cannot exceed its context, responses cannot exceed 1 MiB,
and timeout cannot exceed one hour.

`quality.database` is limited to 4096 bytes and `workflow.task_kind` to 128 bytes. Both must be nonempty and must not
contain control characters. Configuration tables and settings may each be declared only once.

Command-line configuration, database, state, project, format, and color values override defaults where applicable.
Read-only commands do not create, migrate, recover, or repair an external database.
`output.format` and `--format` accept `terminal`, `json`, or `markdown`. Markdown and JSON always disable terminal color.

Operational output is bounded by `output.maximum_output_items`, which defaults to 10,000 and may not exceed
100,000. Persisted history examined or appended by one operation is independently bounded by
`operations.maximum_history_items`, which defaults to 100,000 and may not exceed 1,000,000. State-schema upgrades use
the separate
`operations.maximum_migration_rows` scan budget, which defaults to 1,000,000 and may be raised to the complete
representable state capacity of 1,300,000,000 rows. Publication recovery is bounded by
`operations.maximum_recovery_operations`, which defaults to 100 and may
not exceed 10,000. `operations.maximum_persisted_text_bytes` bounds each state field on both write and read,
defaults to 1 MiB, and may not exceed 16 MiB. `operations.maximum_persisted_total_bytes` independently bounds all
encoded row bytes read or written for one plan revision; it defaults to 64 MiB and may not exceed 2,000,000,000 bytes.
Output limits apply to projects, findings, plans, publication results, tasks, status, and verification results.
Exceeding a limit fails before persistent or harness modification.

