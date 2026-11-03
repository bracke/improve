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
- Require the current authoritative Ada Quality source identity to match the selected assessment before planning.
- Resolve selective-publication prerequisites through the complete plan and existing native task mappings.
- Add an Ada-only Phase 9 gate covering warning-clean builds, 65 AUnit cases, GNATdoc, GNATprove, repository checks, and
  at least 90% measured production-line coverage.
- Add pin-free release manifests, dependency-license evidence, a complete API documentation audit, fingerprinted
  coverage evidence, and an Ada-only clean release-candidate assessment across all 33 quality indicators.

