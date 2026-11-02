# Improve state schema

Improve owns schema version 1 of its state database. It uses the existing `database` crate and its typed rows,
transactions, write-ahead recovery, process locking, and read-only open mode. Ada Quality and model runner state are
never stored here.

## Logical tables

The schema has twelve append-oriented logical namespaces:

| Namespace | Purpose |
| --- | --- |
| `schema_metadata` | Schema version and logical-table manifest |
| `projects` | Ada Quality registry identity and canonical target path |
| `assessment_baselines` | Immutable run and assessment fingerprint references |
| `finding_references` | Normalized findings and unavailable-evidence candidates |
| `plans` | Stable plan identities |
| `plan_revisions` | Immutable plan specifications and planner provenance |
| `remediation_tasks` | Complete Improve task specifications |
| `task_finding_links` | Many-to-many task/finding traceability |
| `task_dependencies` | Validated prerequisite edges |
| `publications` | Improve-to-harness task mappings, populated in Phase 5 |
| `verification_records` | Independent quality outcomes, populated in Phase 6 |
| `operations` | Durable idempotency and recovery journal |

The current database library keeps its catalog on one page. Twelve separately registered six-column physical tables
exceed that catalog capacity, so schema version 1 represents the namespaces in one typed `improve_records` table. Every
row carries a `table_id`, logical identity, parent identity, kind, state, payload, and active flag. Its primary key is a
checked composite of namespace and logical identity. The schema metadata row records all twelve stable namespace names.
This is a physical layout choice; the storage API enforces namespace isolation and logical foreign-key invariants.

## Transactions and identity

Creating a revision writes the baseline, findings, task specifications, links, dependency edges, and operation journal
in one write transaction. A stable planner fingerprint is checked first. If it already exists, the stored immutable
revision is returned instead of inserting duplicate work.

Plan identities use `PLAN-NNNNNN`; task identities use `IMP-NNNNNN`. Draft dependency identities are translated to the
persisted task identities before rows are inserted. Historical evidence is never updated or deleted by plan creation.

Read-only commands use `Database.Open_Read_Only`. They do not create a missing file, register schemas, migrate state, or
perform recovery. Writable open initializes a missing version-1 database; an existing database with missing or different
schema metadata is rejected rather than guessed or silently migrated.
