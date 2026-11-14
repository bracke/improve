# Configuration

`config/improve.toml` is schema version 1. Every value is type- and range-checked. Planning task and per-task finding
limits are positive and bounded at 10,000. The only supported initial evidence selection is `latest_completed`, and
publication is always `candidate`; project harness policy may independently auto-accept a published origin or kind.
Settings are section-qualified. Unknown sections, misplaced or duplicate keys, and files larger than 1 MiB are
rejected.

The reporting snapshot is bounded before it is loaded by `quality.maximum_database_projects`,
`quality.maximum_database_runs`, and `quality.maximum_database_findings`. Their defaults are 10,000,
1,000,000, and 2,000,000 respectively.

Assessment normalization is bounded by `quality.maximum_assessment_findings` and
`quality.maximum_assessment_bytes`. The quality database is rejected before loading when it exceeds
`quality.maximum_database_bytes` (1 GiB by default). Assessment defaults are 10,000 findings and 16 MiB; accepted
maxima are 1,000,000 findings and 256 MiB. The database-size maximum is 2,000,000,000 bytes. Limits are enforced while
the assessment fingerprint is streamed and while deduplicated findings are constructed.

Optional refinement is bounded by `planning.agent_max_context_bytes`, `agent_max_file_bytes`,
`agent_max_response_bytes`, and `agent_timeout_seconds`. Defaults are 131072, 32768, 131072, and 60 respectively.
Context is at least 1024 bytes and at most 10 MiB, a file cannot exceed its context, responses cannot exceed 1 MiB,
and timeout cannot exceed one hour.

`quality.database` is limited to 4096 bytes and `workflow.task_kind` to 128 bytes. Both must be nonempty and must not
contain control characters. Configuration tables and settings may each be declared only once.

Command-line database, state, project, format, and color values override effective configuration where applicable.
Read-only commands do not create, migrate, recover, or repair an external database.

Operational output is bounded by `output.maximum_output_items`, which defaults to 10,000 and may not exceed
100,000. Persisted history examined by one operation is independently bounded by `operations.maximum_history_items`,
which defaults to 100,000 and may not exceed 1,000,000. Publication recovery is bounded by
`operations.maximum_recovery_operations`, which defaults to 100 and may
not exceed 10,000. `operations.maximum_persisted_text_bytes` bounds each state payload on both write and read,
defaults to 1 MiB, and may not exceed 16 MiB. Output limits apply to projects, findings, plans, publication results,
tasks, status, and verification results. Exceeding a limit fails before persistent or harness modification.

