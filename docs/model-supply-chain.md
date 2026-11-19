# Production model supply chain

The optional production compatibility job uses one explicitly identified external model artifact. Improve does not
redistribute it and never writes it into a release archive.

| Field | Value |
| --- | --- |
| Publisher | Qwen |
| Model | Qwen2.5-Coder-0.5B-Instruct-Q2_K GGUF |
| License | Apache-2.0 |
| Source | [Official Qwen GGUF file][model] |
| SHA-256 | `f9bddf294ef15c80bb64a2cdcf15d5b25caf88fb4f4a12383bc9f7a01a09c2e3` |

CI downloads the exact URL recorded in `.github/workflows/ci.yml`, verifies this digest before opening the file, and
records the runtime-reported digest, architecture, byte count, timing, and peak resident memory in its diagnostic
artifact. Release CI generates an SPDX JSON SBOM and GitHub build-provenance/SBOM attestations for Improve binaries.

[model]: https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct-GGUF/blob/main/qwen2.5-coder-0.5b-instruct-q2_k.gguf
