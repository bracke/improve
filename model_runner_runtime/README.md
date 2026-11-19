# Improve Model Runner runtime

This optional project implements `Improve.Refinement.Model_Runner_Client.Session`
with the in-process `Model_Runner.Inference` API. It keeps the core Improve
library independent of model loading while providing a typed, non-CLI path from
bounded planning context to schema-constrained model output.

Build it as its own Alire crate with the repository's pinned toolchain:

```sh
cd model_runner_runtime
alr build
```

The crate imports `improve.gpr` and `model_runner_inference.gpr` from named Alire dependencies; its pin-free
release manifest contains no sibling paths. It builds `bin/improve-model-runner`. Local refinement is explicitly
opt-in:

```toml
[planning]
agent_enabled = true
agent_model = "local-refiner"
agent_model_path = "/models/refiner.gguf"
agent_model_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
```

Use the optional executable with the same arguments as `improve`, for example
`bin/improve-model-runner plan --project example`. The core executable remains free of the full
inference dependency and rejects an enabled agent configuration with an unavailable-dependency diagnostic.

The model identity, path, and expected digest may be overridden with `--agent-model`, `--agent-model-path`, and
`--agent-model-sha256`. `--no-agent` forces deterministic planning. A configured digest is compared with the exact
joined GGUF bytes before refinement.

Call `Open` once, retain the runtime for sequential requests, and pass it to
`Improve.Refinement.Model_Runner_Client.Create`. `Open` compiles Improve's JSON
response schema once and hashes the exact joined GGUF bytes. Hashing is cancellable
and emits byte progress. The runtime name
contains that SHA-256 digest, so an accepted plan's planner provenance identifies
the loaded model bytes as well as the caller's model name. `Close` explicitly
releases both schema and model state and clears the retained digest.

Model loading and generation forward semantic events to the progress observer
in `Open_Options`. Use `Configure_Completion` to replace the cancellation token
or generation observer for subsequent calls. Cancellation is cooperative and
propagates as an interrupted operation so the enclosing plan is not persisted.

The executable renders progress on stderr and maps Ctrl-C to cooperative cancellation during loading, hashing, and
generation. `--progress auto|always|never` selects TTY-aware, forced, or suppressed reporting; `--quiet` suppresses
progress. `doctor` reports runtime/schema readiness, canonical model path, actual digest, architecture, total bytes,
opened file count, and model-pin agreement.

The schema/runtime boundary has a standalone smoke check:

```sh
alr exec -- gprbuild -P tests/runtime_schema_smoke.gpr
tests/bin/runtime_schema_smoke
```

The deterministic end-to-end check creates tiny GGUF files whose constrained
tokens form refinement responses. It exercises open, SHA-256 replacement,
loading/hash/generation progress, multi-token inference, strict decoding,
proposal validation, timeout, cancellation, output/context bounds, identity
mismatch, invalid magic, truncation, unsupported architecture, failed reopen,
and close without downloading a model:

```sh
alr exec -- gprbuild -P tests/runtime_end_to_end.gpr runtime_end_to_end.adb -j1
tests/bin/runtime_end_to_end
```

The signal integration check raises a real host SIGINT during generation and verifies exit 130 without creating the
Improve state database. The C runtime routes it through POSIX signal handling on Linux/macOS and the console-control
handler on Windows, so every CI platform exercises its actual interruption bridge:

```sh
alr exec -- gprbuild -P tests/runtime_signal_interrupt.gpr runtime_signal_interrupt.adb -j1
tests/bin/runtime_signal_interrupt
```

The production-model check requires a lower-case digest pin, opens the caller-supplied GGUF, validates architecture
and byte/part provenance, performs an actual bounded schema-constrained completion, rejects a wrong CLI digest without
persistence, and runs a complete CLI plan whose stored provenance must retain the provider and exact model digest:

```sh
IMPROVE_TEST_MODEL=/models/refiner.gguf \
IMPROVE_TEST_MODEL_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  tests/bin/runtime_external_model
```

Optional `IMPROVE_TEST_MAX_OPEN_SECONDS`, `IMPROVE_TEST_MAX_INFER_SECONDS`, and
`IMPROVE_TEST_MAX_CLI_SECONDS` values enforce wall-time budgets. CI additionally uses GNU `time` to cap peak RSS.

CI runs the deterministic runtime suite on Linux, macOS, and Windows. A scheduled or manually dispatched Ubuntu job
downloads a cached Qwen2.5 Coder 0.5B Q2_K GGUF, verifies its fixed SHA-256, and runs the production completion check.
Jobs have concurrency cancellation and hard timeouts, cache OS-specific Alire/build artifacts, and upload diagnostics
on failure. The repository gate validates every dependency-lock entry against the development workspace pins.
