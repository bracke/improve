# Agent-assisted planning

Agent refinement is optional and advisory. `Improve.Refinement` first builds a deterministic plan, then gives an
explicit noninteractive adapter bounded read-only context and accepts only typed `Task_Proposal` values. No adapter is
required for normal planning, and every adapter failure returns the unchanged deterministic draft.

The context contains project identity, assessment and policy fingerprints, normalized evidence, deterministic task
summaries, optional existing-task summaries, the required proposal schema, and no-follow source excerpts. Source reads
use `Hostkit.Fs.Read_Beneath`; paths outside the registered project, path traversal, and symbolic links are never read.
Context, individual file, response, and wall-clock limits come from the validated planning configuration.

The validator preserves deterministic evidence and acceptance intent. A proposal is rejected if it:

- names an unknown task or changes its category;
- invents, removes, or reorders finding identities;
- removes deterministic file scope or dependencies;
- names a missing, external, traversing, or linked file;
- names an unknown dependency or creates a dependency cycle;
- omits its quality-policy preservation declaration or proposes weakening checks;
- contains invalid control text, duplicates, or exceeds response/task limits.

Accepted text is appended as explicitly advisory detail. It never replaces deterministic goals, acceptance, or
verification criteria. Confidence may only stay the same or decrease. The refined plan receives a new deterministic
fingerprint and records the adapter identity in planner provenance before normal immutable persistence.

The current model_runner framework does not expose a lightweight “refine this plan” call independent of model session
and harness execution. Improve therefore does not shell out or repurpose `/work`; a future model-backed integration
must implement the typed adapter directly and use a documented noninteractive model API. The adapter call is enclosed
by Improve's wall-clock deadline. Unavailable, timed-out, malformed, exceptional, and rejected responses all preserve
the deterministic draft.
