with Improve.Config;
with Improve.Model;
with Improve.Storage;

--  Application use cases shared by the CLI and other adapters.
package Improve.Operations is
   --  Shared application invariants for operation-specific child packages.

   procedure Require_Project_Identity
     (Expected, Actual : Improve.Model.Project_Reference);
   --  Reject a project resolved from a different quality database or root.
   --  @param Expected Database-qualified identity stored with remediation state.
   --  @param Actual Identity resolved from the selected Ada Quality database.

   function Storage_Read_Limits
     (Settings : Improve.Config.Settings) return Improve.Storage.Read_Limits;
   --  Derive hard persistence reconstruction limits from validated configuration.
   --  @param Settings Validated Improve configuration.
   --  @return Limits for one immutable plan revision.
end Improve.Operations;
