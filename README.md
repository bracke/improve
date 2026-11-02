# Improve

Improve turns completed [Ada Quality](https://github.com/bracke/ada_quality) assessments into deterministic,
reviewable remediation plans and publishes approved work as native model_runner tasks.

It has three strict ownership boundaries:

- Ada Quality owns measurement evidence; Improve opens that database read-only.
- Improve owns plans, revisions, provenance, publication mappings, and verification history.
- model_runner owns published task definitions, execution state, readiness, and agent workflow.

Improve never measures or edits a target project and does not execute remediation agents.

## Build

```sh
alr build
./bin/improve help
```

The local development manifest pins the sibling repositories used by this workspace. See
[`docs/implementation-plan.md`](docs/implementation-plan.md) for the phased gates and
[`docs/architecture.md`](docs/architecture.md) for the integration boundaries.

