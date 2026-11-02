# Improve

Improve turns completed [Ada Quality](https://github.com/bracke/ada_quality) assessments into deterministic,
reviewable remediation plans and publishes approved work as native model_runner tasks.

It has three strict ownership boundaries:

- Ada Quality owns measurement evidence; Improve opens that database read-only.
- Improve owns plans, revisions, provenance, publication mappings, and verification history.
- model_runner owns published task definitions, execution state, readiness, and agent workflow.

Improve never measures or edits a target project and does not execute remediation agents.
Optional planning refinement is available through a bounded typed adapter; deterministic planning remains the fallback.
Operational `tasks` and `status` views report stored work without mutating state, while `recover` safely reconciles an
interrupted native task publication by its stable Improve origin.

## Build

```sh
alr build
./bin/improve help
```

## Test and release gate

All repository tooling is implemented in Ada. Build the tool executables and run the complete Phase 9 gate with:

```sh
alr exec -- gprbuild -P tools/improve_tools.gpr -p -j1
tools/bin/check_phase_9
```

The gate performs warning-clean application and test builds, runs the 58-case AUnit suite, checks repository policy,
audits the public API with GNATdoc, proves the root digest package with GNATprove, and requires at least 90% measured
production-line coverage. `alr test` invokes the same Ada gate.

The local development manifest pins the sibling repositories used by this workspace. See
[`docs/implementation-plan.md`](docs/implementation-plan.md) for the phased gates and
[`docs/release-readiness.md`](docs/release-readiness.md) for the release evidence.

