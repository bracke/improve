# Architecture

Improve consumes one immutable `Ada_Quality.Reporting.Session`, builds deterministic remediation specifications, and
publishes approved specifications through `Model_Runner.Framework.Tasks.Create` in a harness transaction.

The CLI is a presentation adapter. Typed application use cases live below `Improve.Operations`: planning owns
generation and immutable history, publication and verification enforce evidence and contract rules, inspection
assembles assessment-aware task/status models, and reconciliation synchronizes cached harness state. These operations
own project-identity checks, source and policy preconditions, journaling, and persistence. Terminal and JSON rendering
do not participate in domain decisions.

Domain exception types provide stable diagnostic categories. The CLI maps those categories through the messages
catalog and supplies escaped technical detail as data; domain and storage packages do not construct terminal or JSON
presentation.

Application-operation outputs are defined in `Improve.Results`; persistence-neutral plan, publication, verification,
and journal state is defined separately in `Improve.State`. CLI, terminal, JSON, task, and workflow adapters therefore
do not depend on the storage adapter. `Improve.Storage` remains the transactional facade; physical namespace constants,
canonical row mapping, and key construction are isolated in the private `Improve.Persistence_Schema` unit, while typed
payload codecs and validation remain separate persistence components. Transactional logical-ID reservation is isolated
in the private `Improve.Storage.Allocation` child, so normal writes do not scan namespace history.

Task inspection obtains only the latest completed run identity needed for freshness classification. It does not decode
complete assessment evidence; planning and verification retain responsibility for bounded evidence validation.

Quality repositories and Improve stores are controlled owners. Operations close them explicitly only to release a
successful phase early; exceptional paths rely on finalization so cleanup cannot replace the originating exception.
Improve storage checks transaction start, commit, and rollback results at the persistence boundary, and explicit store
closure reports dependency persistence or handle-close failures. Finalization remains best-effort during unwinding.
If first-time initialization fails, Improve removes only the database artifacts created by that call so retrying the
previously absent state path starts from a clean boundary.

The assessment database is never created, migrated, recovered, or written by Improve. Improve's own state database
is a separate boundary. A model_runner commit and an Improve mapping commit are deliberately treated as two durable
operations joined by a stable origin identifier and recovery, not as a distributed transaction.

Quality reads are bounded before the reporting snapshot is materialized by a configurable database-file limit.
Assessment identity is then computed with the shared canonical streaming SHA-256 builder, which enforces the configured
per-assessment evidence limit without creating another complete copy of the evidence.
Complete assessment evidence, normalized remediation findings, and working-source content have separate limits.
Application operations receive them through one typed evidence-limit value so publication and recovery cannot drift
from planning policy.
Operational rejection limits are not part of semantic plan identity: changing a limit without changing accepted
evidence, task grouping, or review policy does not create a new immutable revision.

Approval and publication journaling bind the semantic plan identity to a separate canonical digest of the complete
persisted plan content. The content digest covers normalized provenance, creation chronology, findings, logical task
identities, and full task contracts. Reloaded or recovered work must match that digest, so child-row corruption cannot
inherit an earlier approval or publication authorization.

Plan generation requires the current authoritative Ada Quality source fingerprint to match the selected completed
assessment. Publication applies a second, harness-state-aware `working-sha256-v4` fingerprint to detect authored
changes after planning without treating model_runner's own operational state as a source edit. The working identity is
a length-delimited SHA-256 stream over sorted relative paths and bounded file contents, so path/content boundaries
cannot produce the same byte stream accidentally.
Improve state, full-text, and database-provided WAL artifacts are excluded through their actual configured paths.
The baseline additionally authenticates the selected assessment's complete typed evidence. Publication therefore
rejects evidence replacement even when the run, source, policy, and toolchain metadata remain unchanged.

The model_runner repository exposes an explicit source closure through the lightweight `model_runner_framework` crate.
The publication adapter therefore imports a project with no executable, inference backend, or main-unit target.
Execution-specific task eligibility, workspace, and full consistency checks are registered by the full harness when
linked. An unavailable check fails closed; it cannot silently make a task executable or conceal an active workspace.
No framework record or transaction behavior is copied here.

Optional planning assistance sits behind `Improve.Refinement.Adapter`. The adapter receives bounded immutable context
and returns typed proposals; it owns no plan, quality, project, or harness state. Improve validates and fingerprints the
result before normal persistence. model_runner's interactive `/work` path remains exclusively the execution workflow.
`Improve.Refinement.Model_Adapter` supplies a concrete schema-aware bridge to any in-process typed model client.
`Improve.Refinement.Model_Runner_Client` implements that client over an optional model_runner inference session while
keeping session ownership outside Improve and preserving the same validation and fallback path. The separate
`model_runner_runtime` crate supplies the local GGUF implementation and strict JSON codec without making the full
inference engine a dependency of the core executable. Its project imports named Alire projects rather than repository
paths and has its own pin-free publication manifest.
The runtime exposes typed model provenance—canonical path, digest, architecture, bytes, and file count—to `doctor`.
Its cancellation token propagates through the adapter as an interrupted operation and is checked before plan storage.

Read-only usability features remain adapters over deterministic application state. Plan comparison evaluates immutable
revision provenance and individual contract fields without persistence; audit bundles join exact plan, approval,
publication, and verification history; finding filters run only after evidence normalization. Core `doctor` opens
owned dependencies read-only, while the optional runtime adds a read-only GGUF/schema and digest-pin preflight.
Markdown, JSON, terminal, completion, and man-page output contain no domain decisions.

Recovery orchestration belongs to `Improve.Operations.Recovery`, alongside the other application use cases. The older
`Improve.Recovery` unit is retained only as a compatibility adapter and contains no recovery policy.

Improve is distributed as a CLI executable, not as an Alire library crate. Its supported external interface is the CLI
and its versioned JSON documents. The root `Improve` unit provides shared versioning and deterministic identity support;
child package specifications are implementation contracts used by the executable and tests, not a compatibility-stable
third-party Ada API. GNATdoc therefore audits the root unit, while the complete CLI and JSON contracts are maintained in
`docs/cli-reference.md` and exercised by golden and schema-oriented tests.

