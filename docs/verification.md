# Verification

Verification has three independently persisted scopes: task, complete plan, and complete project assessment. A
`verify --task` invocation records only the selected task outcome. It cannot create or replace a plan or project
conclusion. A full project invocation records per-task results plus distinct plan and project aggregate records, so
both scopes can evaluate the same assessment without identity conflicts.

Finding matching uses every current finding regardless of task-generation severity thresholds. A matching fingerprint
remains outstanding when its severity changes; severity reduction alone is not resolution evidence.

`improve verify` evaluates an existing completed Ada Quality assessment. It never starts a measurement and never moves
a model runner task. `improve refresh` performs the same evidence evaluation after reconciling published task states;
an unresolved refresh is reported in its document but does not make the reconciliation command fail.

The verifier requires the same registered project, a completed assessment newer than the plan baseline when freshness
is configured, and compatible policy and toolchain fingerprints according to configuration. A changed source
fingerprint is expected during remediation and does not by itself make evidence incomparable.

Each task is evaluated against all linked baseline findings:

- a passing current indicator resolves its linked baseline deficiencies;
- the same stable finding fingerprint remains outstanding;
- aggregate indicator failures remain outstanding while the indicator still violates policy;
- blocked, errored, unavailable, inapplicable, or uncertain semantic evidence is inconclusive;
- a mixture of resolved and outstanding linked findings is partially resolved;
- a deficiency returning after a recorded verified result is regressed.

Regression history is contract-specific. A prior verified record qualifies only when its immutable task-contract
fingerprint equals the contract currently being evaluated. Reuse of a logical task ID across a changed contract does
not carry resolution history forward without an explicit future compatibility rule.

When configured, a new critical finding also makes the report regressed. A task is verified only if every mandatory
linked deficiency has comparable evidence and is resolved. Overall outcome precedence is regression, inconclusive,
still failing, partial resolution, then verified.

An unrelated new critical finding regresses the project assessment and command result, while the complete plan outcome
continues to describe only its linked remediation work.

Verification records identify their scope, optional task, completed assessment, comparability decision, outcome, and
explanation. They also identify the exact immutable plan revision and task or plan acceptance-contract fingerprint.
Records are append-only and idempotent for the same scope, revision, contract, and assessment evidence. Distinct plan
revisions can therefore be evaluated independently against the same completed assessment. JSON output is
schema-versioned and verification returns exit code 1 for every requested outcome other than `verified`; invalid or
incomplete assessment selection returns the normal unavailable-evidence error instead.

Status never presents a historical conclusion as current quality. It compares the assessment named by the most recent
exact-revision plan and project verification records with the latest completed assessment, reporting older evidence
as a previous result and leaving the current assessment unverified.

The same rule governs finding aggregation. Current verification drives resolved, regressed, inconclusive, and
superseded counts; historical verified evidence is retained in a separate previously-resolved count, and absent current
evidence is explicitly unverified.
