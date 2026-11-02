# Deterministic remediation rules

`Improve.Rules` is a total registry indexed by `Ada_Quality.Types.Indicator_Id`. Each of the 33 indicators has a typed
strategy class, task title, goal, acceptance condition, and measurement verification condition. Adding a new Ada Quality
indicator therefore causes a compile-time obligation to extend the registry; the planner has no generic “fix quality”
fallback.

## Planning behavior

`Improve.Planner` groups findings only when indicator, candidate kind, diagnostic rule, and semantic subject all match.
Groups are split at `planning.maximum_findings_per_task`, and the complete plan is rejected before publication if it
would exceed `planning.maximum_tasks_per_plan`.

Priority has a deterministic order: critical, high, normal, low. It derives from the strongest linked severity, with
security, build, dependency, and release impact raising priority where applicable. Severity alone never causes findings
with unrelated subjects to be grouped.

Every task includes a goal, problem statement, evidence and finding fingerprints, bounded scope, explicit exclusions,
implementation requirements, acceptance conditions, measurement verification, confidence, and review policy. A task
never represents a hypothesized root cause as established evidence.

Aggregate `TST-03` evidence is intentionally special: when no file- or unit-level coverage evidence exists, the planner
creates an investigation task instead of inventing parser, boundary, or other test scopes. Focused implementation tasks
can be produced only from findings that establish those subjects.

`Improve.Dependencies.Validate` rejects missing targets, self-dependencies, duplicate identities, duplicate edges, and
cycles. Generated task and plan draft identities are stable digests of the assessment, planner configuration, grouping,
and acceptance contract. Creation timestamps are deliberately excluded from deterministic identity.

Persistent numeric plan and task identities are assigned by the Improve database in Phase 4. Until then, only
`plan --dry-run` is enabled; attempting to create a persistent plan fails without modifying state.
