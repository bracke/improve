with Improve.Results;
with Improve.Storage;

--  Read-only audit evidence export.
package Improve.Operations.Audit is
   --  Read-only audit evidence export for one immutable remediation revision.

   function Run
     (State_Path : String;
      Plan_Id    : String;
      Revision   : Natural := 0;
      Maximum    : Positive := Improve.Storage.Default_Query_Maximum;
      Limits     : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits)
      return Improve.Results.Audit_Bundle;
   --  Load one exact plan, approval decision, and associated history without modifying state.
   --  @param State_Path Existing Improve state database path.
   --  @param Plan_Id Stable logical plan identity.
   --  @param Revision Exact immutable revision, or zero for the latest revision.
   --  @param Maximum Maximum publication and verification records to materialize.
   --  @param Limits Hard persistence reconstruction limits.
   --  @return Selected immutable plan and its approval, publication, and verification evidence.
end Improve.Operations.Audit;
