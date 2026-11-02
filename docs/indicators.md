# Ada Quality evidence ingestion

Phase 2 consumes the 33 indicators registered by `Ada_Quality.Types.Indicator_Id` in registry order. An assessment is
accepted only when it is complete, contains exactly one valid result for every registered indicator, and belongs to the
selected project. Improve reads the assessment through `Ada_Quality.Reporting`; it never opens the Ada Quality database
for writing.

## Classification

| Execution | Compliance | Improve classification |
| --- | --- | --- |
| `Succeeded` | `Pass` | Excluded from remediation |
| `Succeeded` | `Violation` | Remediation candidate |
| `Succeeded` | `Unknown` | Invalid Ada Quality evidence |
| `Blocked` or `Failed` | `Unknown` | Diagnostic candidate |
| `Errored`, `Not_Run`, or `Running` | `Unknown` | Investigation candidate |
| `Not_Applicable` | `Not_Applicable` | Excluded |

The table follows the schema-version-3 validity rules enforced by `Ada_Quality.Types.Is_Valid`. A violated indicator
without source-level findings produces an indicator-level candidate, so unavailable diagnostic detail cannot silently
hide a failing requirement.

## Identity and paths

Source-level candidates retain the Ada Quality fingerprint. Deduplication additionally includes project, indicator,
rule, and semantic subject, preventing accidental merging across projects or rules. Paths must be relative to the
registered project and may not contain parent traversal, empty components, drive prefixes, or absolute roots.

Selection without `--run` chooses the newest completed run. Newer interrupted or incomplete runs are visible in the
source history but do not replace that baseline.
