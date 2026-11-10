--  Deterministic command-line parsing, separate from command execution.
package Improve.CLI.Parsing is
   function Parse (Arguments : String_Vectors.Vector) return Invocation;
   --  Parse and validate arguments without opening databases or writing output.
end Improve.CLI.Parsing;
