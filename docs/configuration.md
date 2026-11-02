# Configuration

`config/improve.toml` is schema version 1. Every value is type- and range-checked. Task and finding limits are
positive and bounded at 10,000. The only supported initial evidence selection is `latest_completed`, and publication
is always `candidate`; project harness policy may independently auto-accept a published origin or task kind.

Command-line database, state, project, format, and color values override effective configuration where applicable.
Read-only commands do not create, migrate, recover, or repair an external database.

