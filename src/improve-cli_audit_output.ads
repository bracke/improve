with Improve.CLI;
with Improve.Config;

--  Audit export and verification orchestration behind the CLI boundary.
private package Improve.CLI_Audit_Output is
   function Render
     (Item     : Improve.CLI.Invocation;
      Settings : Improve.Config.Settings) return String;
   --  Export an audit artifact or verify one with an optional independent trust anchor.
end Improve.CLI_Audit_Output;
