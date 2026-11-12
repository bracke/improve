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

The current model_runner framework does not expose a lightweight “refine this plan” call independent of model session
and harness execution. Improve therefore does not shell out or repurpose `/work`; a future model-backed integration
must implement the typed adapter directly and use a documented noninteractive model API. Each adapter must enforce the
supplied deadline cooperatively and report `Agent_Timed_Out`; Improve never asynchronously aborts adapter code while it
may own external resources. Unavailable, timed-out, malformed, exceptional, and rejected responses all preserve the
deterministic draft.
