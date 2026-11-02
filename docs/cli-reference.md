# CLI reference

```text
improve <command> [options]
```

Commands are `projects`, `findings`, `plan`, `apply`, `tasks`, `status`, `refresh`, `verify`, `recover`, `config`,
`help`, and `version`. Global options may precede or follow the command. Unknown, repeated, missing, malformed, and
command-incompatible options are rejected deterministically with exit code 2.

`--format json` writes exactly one versioned JSON document to standard output and disables ANSI styling regardless
of `--color`. Diagnostics are written only to standard error. Inspection commands return zero when inspection
succeeds even when quality findings exist; verification returns one when its requested criteria remain unresolved.

Exit codes are 0 for success, 1 for a completed negative verification, 2 for invalid input, 3 for unavailable
evidence or project state, and 4 for storage, integrity, publication, or internal failure.

