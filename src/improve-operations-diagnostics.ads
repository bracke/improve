with Improve.Config;
with Improve.Results;
with Improve.Storage;

--  Read-only local environment and persistence diagnostics.
package Improve.Operations.Diagnostics is
   --  Bounded read-only checks over local Improve integration prerequisites.

   function Run
     (Quality_Path     : String;
      State_Path       : String;
      Project_Selector : String;
      Settings         : Improve.Config.Settings;
      Resolve_Release  : Boolean := False;
      Limits           : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits)
      return Improve.Results.Diagnostic_Report;
   --  Inspect local configuration, quality evidence, and Improve state without creating or repairing anything.
   --  @param Quality_Path Selected Ada Quality database path.
   --  @param State_Path Selected Improve state database path.
   --  @param Project_Selector Optional project identity or name to resolve.
   --  @param Settings Validated effective configuration.
   --  @param Resolve_Release Whether to resolve the staged pin-free release manifest through Alire.
   --  @param Limits Hard persistence limits.
   --  @return Ordered diagnostic report.
end Improve.Operations.Diagnostics;
