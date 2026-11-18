--  Validator for the JSON Schema subset used by the report schemas.
--
--  Supported keywords: `$ref` (local and `common.schema.json` references), `type`, `properties`, `required`,
--  `additionalProperties: false`, `items`, `maxItems`, `enum`, `const`, `minimum`, `maximum`, `minLength`, `oneOf`, and
--  `pattern` limited to anchored literals, character classes, alternation groups, `{n}` repetition, and the error
--  code pattern used by the Improve schema. The
--  annotations `$schema`, `$id`, `$defs`, `title`, and `description` are accepted. Any other keyword, an
--  `additionalProperties` other than `false`, or a list of types is reported as unsupported rather than ignored.
package Improve_JSON_Schema_Testing is
   --  Validator for the JSON Schema subset used by the report schemas.

   function Validate (Schema_Directory, Schema_File, Document : String) return String;
   --  Validate a JSON document against a schema file.
   --  @param Schema_Directory Directory containing every schema file.
   --  @param Schema_File Schema file name such as `summary.schema.json`.
   --  @param Document JSON text.
   --  @return Empty string when valid, otherwise the first violation with its JSON path.

   function Matches (Pattern, Text : String) return Boolean;
   --  Match the supported pattern subset.
   --  @param Pattern Anchored pattern.
   --  @param Text Candidate.
   --  @return True on a complete match.
end Improve_JSON_Schema_Testing;

