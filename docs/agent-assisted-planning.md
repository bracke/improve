# Agent-assisted planning

Agent refinement is optional and advisory. `Improve.Refinement` first builds a deterministic plan, then gives an
explicit noninteractive adapter bounded read-only context and accepts only typed `Task_Proposal` values. No adapter is
required for normal planning, and every adapter failure returns the unchanged deterministic draft.

The context contains project identity, assessment and policy fingerprints, typed normalized evidence, typed
deterministic and existing-task specifications, the required proposal schema, and no-follow source excerpts.
Diagnostic and source text are explicitly untrusted data rather than a line-oriented instruction stream. Source reads
use `Hostkit.Fs.Read_Beneath`; paths outside the registered project, path traversal, and symbolic links are never read.
Context, individual file, response, and deadline limits come from the validated planning configuration.
Complete deterministic task specifications are admitted before optional evidence and source excerpts, so context
truncation cannot leave an adapter with evidence but no actionable task contract.

The validator preserves deterministic evidence and acceptance intent. A proposal is rejected if it:

- names an unknown task or changes its category;
- invents, removes, or reorders finding identities;
- removes deterministic file scope or dependencies;
- names a missing, external, traversing, or linked file;
- names an unknown dependency or creates a dependency cycle;
- omits its quality-policy preservation declaration;
- changes deterministic title, goal, scope, acceptance, or verification text;
- contains duplicate or oversized collections, or exceeds response/task limits.

An accepted proposal may add authorized source files or existing task dependencies and may lower planning confidence.
Free-text execution changes are not accepted because their policy meaning cannot be validated deterministically. The
refined plan receives a new deterministic fingerprint and records the adapter identity in planner provenance before
normal immutable persistence.

The lightweight model_runner task framework does not own inference sessions. Improve therefore does not shell out or
repurpose `/work`. `Improve.Refinement.Model_Adapter` is the concrete integration boundary for an in-process model
client: it passes the bounded typed context, required answer schema, cooperative deadline, and maximum response bytes
to the client, then returns the normal typed `Agent_Response` through unchanged validation and deterministic fallback.
`Improve.Refinement.Model_Runner_Client` binds an explicit model identity to a typed optional session.

`model_runner_runtime/improve_model_runner_runtime.gpr` provides that optional session using
`Model_Runner.Inference`. It compiles Improve's response schema once at open, serializes context through
`Improve.Refinement.Codec`, performs bounded schema-constrained generation, strictly decodes the returned JSON, and
maps model_runner completion states to Improve response states. Open hashes the exact joined GGUF bytes, and the
runtime identity embeds that SHA-256 digest; accepted planner provenance therefore binds both the caller's model name
and the model bytes. The provider identity and model digest are also stored as typed plan and audit fields, so readers
do not need to parse `Planner_Id`. Loading, hashing, and generation forward semantic progress events, while a
replaceable cooperative token supports cancellation without asynchronous abort. The runtime owns only model and schema
resources; it does not duplicate model_runner task records or lifecycle logic. Core Improve remains usable without the
runtime project.
Improve never asynchronously aborts adapter code while it may own external resources.
Unavailable, timed-out, malformed, exceptional, and rejected responses all preserve the deterministic draft.

The optional `improve-model-runner` executable reads the normal Improve configuration and injects this runtime into
`improve plan`. Refinement requires the three explicit `planning.agent_enabled`, `agent_model`, and
`agent_model_path` settings; the core `improve` executable fails clearly if refinement is enabled without the optional
runtime rather than silently ignoring the request.

An optional `agent_model_sha256` pins the exact joined GGUF bytes. The optional executable reports loading, hashing,
and generation progress on stderr according to `--progress auto|always|never`. Ctrl-C aborts planning with exit 130
before plan persistence instead of selecting deterministic fallback. `doctor` reports GGUF/schema readiness, the
actual digest, canonical path, architecture, byte size, file count, and digest-pin agreement.

The runtime CI matrix builds and executes deterministic inference checks on Linux, macOS, and Windows. Each platform's
signal test raises a real SIGINT during generation and asserts exit 130 with no state database. The deterministic suite
also rejects corrupt, truncated, and unsupported GGUF inputs. A separate scheduled or manual job verifies a fixed
SHA-256 before exercising a full CLI plan and checking persisted provider/model provenance against a production Qwen
GGUF. It enforces explicit open, inference, CLI, and peak-RSS budgets and uploads its measurements as CI diagnostics.
