# Improve state schema

Improve owns schema version 5 of its state database. It uses the existing `database` crate and its typed rows,
transactions, write-ahead recovery, process locking, and read-only open mode. Ada Quality and model runner state are
never stored here.

## Logical tables

The schema has fourteen append-oriented logical namespaces:

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
| `task_details` | Normalized large execution-contract fields owned by remediation tasks |
| `task_identities` | Indexed logical-task-to-revision history used by exact historical lookup |

The current database library keeps its catalog on one page. Fourteen separately registered physical tables exceed that
catalog capacity, so the schema represents the namespaces in one typed `improve_records` table. Every
row carries a `table_id`, logical identity, parent identity, kind, state, payload, and active flag. Its primary key is a
checked composite of namespace and logical identity. The schema metadata row records all fourteen stable namespace
names.
This is a physical layout choice; the storage API enforces namespace isolation and logical foreign-key invariants.

## Transactions and identity

Creating a revision writes the baseline, findings, task specifications, links, and dependency edges in one write
transaction. A stable planner fingerprint is checked first. If it already exists, the stored immutable
revision is returned instead of inserting duplicate work.

Plan identities use `PLAN-NNNNNN`; task identities use `IMP-NNNNNN`. Draft dependency identities are translated to the
persisted task identities before rows are inserted. Historical evidence is never updated or deleted by plan creation.

When a newer immutable revision contains the same task category, title, acceptance contract, and exact finding set as
the immediately preceding revision, it reuses that task's logical `IMP-NNNNNN` identity. The new revision still gets a
new physical task row and remains immutable. Changed or newly introduced work receives a new logical identity. This
keeps unaffected work and publication history stable while preserving complete revision history.

Task rows form a persistent logical-task-to-revision index. Historical lookup selects the newest revision containing
the requested `IMP-NNNNNN` identity, or an explicitly requested revision, even when the task is absent from the plan's
current revision.

Project and plan keys include the canonical Ada Quality database identity, registry ID, and canonical project path.
Numeric project IDs are never treated as globally unique across independent quality databases.
Plans and assessment baselines reference the local `projects` row. The project row stores the database-qualified Ada
Quality identity, while each revision references its normalized baseline. Revision payload provenance is retained for
auditing and checked against those authoritative relationships when loaded.
The baseline also stores an assessment-specific fingerprint over the complete typed indicator results, measurements,
and findings. Publication re-reads the exact run and requires this fingerprint to match, so unchanged run metadata
cannot conceal replaced evidence. The database-wide reporting snapshot remains audit provenance, not semantic plan
identity.

Verification identity includes the stable plan ID, immutable plan revision, completed assessment, evaluation scope,
and acceptance-contract fingerprint. Task-scoped records use the dependency-qualified effective contract; plan and
project records retain the immutable plan fingerprint. Thus two revisions can be evaluated against one assessment
without conflicting, while an identical evaluation remains idempotent.

Read-only commands use `Database.Open_Read_Only`. They do not create a missing file, register schemas, migrate state, or
perform recovery. Writable open initializes a missing version-5 database and upgrades older supported state before
writing. The version-3 migration backfills indexed plan parents for publication and verification records; the version-4
migration builds the logical-task history index. Version 5 links plans and baselines to database-qualified local
project references and validates duplicated provenance so
normal plan-scoped access does not scan their complete history. Read-only access remains compatible with older state
without migrating it. Missing or unknown schema metadata is rejected rather than guessed.

Version-5 migration bounds plan count, revision count, and payload size before updating data. Summary and full-plan
reads use the same normalized project and baseline relationships; duplicated revision provenance remains an audited
consistency check rather than a second authority.

Verification evidence is append-only by evaluation scope and completed assessment. Task, complete-plan, and
complete-project records use distinct identities. Repeating an evaluation at the same scope is idempotent; a
conflicting outcome at that exact scope is rejected without preventing another valid scope from evaluating the same
assessment. Publication mappings are qualified by a dependency-qualified effective task binding. They preserve
immutable Improve, harness, binding, and origin identities while allowing only their cached harness-owned runtime state
to be reconciled. Different authored contracts or prerequisite bindings for one continuing logical task therefore
retain separate historical native mappings.
Publication and verification readers revalidate the stored plan revision and exact effective contract before exposing
records. A payload with a valid plan identity but an unknown revision or mismatched contract is rejected as corrupt.

Mandatory review approval is an append-only `operations` event keyed by stable plan identity and exact revision. The
event also stores the immutable revision fingerprint. Publication accepts the approval only when all three values
match, so a subsequent revision requires a separate approval even when some logical task identities are retained.

## Publication operation journal

Before a non-preview publication opens the harness store, Improve verifies exact-revision approval and appends a
`started` operation containing the plan identity, immutable revision, fingerprint, resolved native task kind, and exact
ordered task identities. Its stable key combines the revision, task kind, and task selection, so retrying the same
authorization reuses the entry. After the harness transaction commits, Improve records the native task mappings and
appends a `completed` child entry in its own transaction.

The two databases are deliberately not treated as one atomic store. If the process stops between those commits,
`recover` reads the unmatched `started` entry and republishes through model_runner's origin-aware idempotency contract.
Only after verified mappings are stored is the operation completed. Approval events remain separate and are never
interpreted as pending publications. Plan persistence does not write into the publication-operation namespace;
completion matching uses both the operation key and explicit parent identity.

Configured persistence limits apply consistently to full loads, summaries, migrations, contract validation, and
history reads and writes. Schema migration is bounded by the same limits supplied when writable state is opened.
Entity-specific typed codecs own publication, verification, approval, and publication-operation payloads. Writers
validate the complete encoded payload before committing it, and readers enforce the same byte contract while decoding.
