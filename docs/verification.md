# Verification

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

When configured, a new critical finding also makes the report regressed. A task is verified only if every mandatory
linked deficiency has comparable evidence and is resolved. Overall outcome precedence is regression, inconclusive,
still failing, partial resolution, then verified.

Verification records identify the task, completed assessment, comparability decision, outcome, and explanation. They
are append-only and idempotent for the same task/assessment evidence. JSON output is schema-versioned and verification
returns exit code 1 for every outcome other than `verified`; invalid or incomplete assessment selection returns the
normal unavailable-evidence error instead.
