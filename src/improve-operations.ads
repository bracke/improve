with Improve.Model;

--  Application use cases shared by the CLI and other adapters.
package Improve.Operations is
   --  Shared application invariants for operation-specific child packages.

   procedure Require_Project_Identity
     (Expected, Actual : Improve.Model.Project_Reference);
   --  Reject a project resolved from a different quality database or root.
   --  @param Expected Database-qualified identity stored with remediation state.
   --  @param Actual Identity resolved from the selected Ada Quality database.
end Improve.Operations;
