# Configuration

`config/improve.toml` is schema version 1. Every value is type- and range-checked. Task and finding limits are
positive and bounded at 10,000. The only supported initial evidence selection is `latest_completed`, and publication
is always `candidate`; project harness policy may independently auto-accept a published origin or task kind.

Optional refinement is bounded by `planning.agent_max_context_bytes`, `agent_max_file_bytes`,
`agent_max_response_bytes`, and `agent_timeout_seconds`. Defaults are 131072, 32768, 131072, and 60 respectively.
Context is at least 1024 bytes and at most 10 MiB, a file cannot exceed its context, responses cannot exceed 1 MiB,
and timeout cannot exceed one hour.

Command-line database, state, project, format, and color values override effective configuration where applicable.
Read-only commands do not create, migrate, recover, or repair an external database.

