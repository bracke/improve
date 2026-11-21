--  Deterministic command-line parsing, separate from command execution.
private package Improve.CLI.Parsing is
   function Parse (Arguments : String_Vectors.Vector) return Invocation;
   --  Parse and validate arguments without opening databases or writing output.
   --  @param Arguments Ordered arguments excluding the executable name.
   --  @return Fully validated invocation.
end Improve.CLI.Parsing;
