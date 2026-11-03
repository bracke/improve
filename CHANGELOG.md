# Changelog

## 0.1.0 — 2026-11-03

- Establish the standalone Ada 2022 crate, strict CLI contract, typed quality ingestion, and deterministic indicator
  strategy registry.
- Complete the real Ada Quality and model_runner end-to-end release workflow, including remeasurement and independent
  verification without duplicate plans or harness tasks.
- Preserve logical Improve task identities for unchanged work across immutable plan revisions.
- Separate project-level regression outcomes from task-level resolution and constrain regression history by assessment
  order.
- Enforce append-only approval of exact immutable plan revisions before native task publication.
- Detect current authored-source changes before publication while excluding harness-owned and runtime state.
- Preserve direct inspection and verification of tasks omitted from newer revisions, with exact `--revision` lookup.
- Require both harness completion and independent quality resolution before reporting a task as fully verified.
- Persist task, plan, and project verification at separate scopes and match current findings without severity filters.
- Attribute verification evidence to an exact plan revision and immutable task or plan acceptance contract.
- Require the current authoritative Ada Quality source identity to match the selected assessment before planning.
- Resolve selective-publication prerequisites through the complete plan and existing native task mappings.
- Prevent recovery from creating missing native tasks after approval or source preconditions become stale.
- Scope status quality to the latest completed assessment and label older plan or project verification as historical.
- Bind derived task verification status to the latest applicable completed assessment while retaining historical evidence.
- Restrict regression history to prior verification of the exact immutable task contract.
- Require replanning when a newer completed assessment changes quality policy before publication.
- Qualify project history by Ada Quality database identity and canonical project path, rejecting cross-database ID reuse.
- Apply database-qualified project identity to task lists and individual task ownership checks.
- Prevent historical regression, supersession, and other quality outcomes from becoming current task status.
- Scope finding summaries to current verification and expose historical resolution separately.
- Canonically fingerprint every planning input, finding, generated task contract, dependency, and planner version so
  configuration or evidence changes cannot collide with an earlier immutable revision.
- Qualify native origins and publication mappings by the complete execution contract, replacing changed definitions
  without losing logical task continuity and reusing native tasks only for demonstrably identical work.
- Preserve the complete goal, problem, evidence, relevant files, scope, exclusions, requirements, acceptance, and
  verification contract in native model_runner task definitions.
- Exercise contract-qualified task and status reporting with distinct historical and replacement native states.
- Keep database-wide reporting snapshot identity as audit provenance while deriving semantic plan identity from the
  selected project's complete typed assessment evidence, preventing unrelated measurements from creating revisions.
- Add an Ada-only Phase 9 gate covering warning-clean builds, 81 AUnit cases, GNATdoc, GNATprove, repository checks, and
  at least 90% measured production-line coverage.
- Add pin-free release manifests, dependency-license evidence, a complete API documentation audit, fingerprinted
  coverage evidence, and an Ada-only clean release-candidate assessment across all 33 quality indicators.

