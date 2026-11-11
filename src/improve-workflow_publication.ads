with Improve.Model;
with Improve.Storage;
with Improve.Workflow;

--  Internal native publication transaction implementation.
package Improve.Workflow_Publication is
   --  Internal publication engine separated from the public workflow facade.

   function Execute
     (Project_Directory : String;
      Plan              : Improve.Model.Plan_Revision;
      Requested_Kind    : String;
      Existing          : Improve.Storage.Publication_Vectors.Vector :=
        Improve.Storage.Publication_Vectors.Empty_Vector;
      Selected_Task_Ids : Improve.Model.UString_Vectors.Vector :=
        Improve.Model.UString_Vectors.Empty_Vector;
      Existing_Only     : Boolean := False;
      Dry_Run           : Boolean := False) return Improve.Workflow.Publication_Result;
   --  Build and apply one validated, dependency-ordered native publication transaction.
   --  @param Project_Directory Canonical initialized model_runner project root.
   --  @param Plan Exact immutable plan revision to publish.
   --  @param Requested_Kind Configured native remediation task kind or auto.
   --  @param Existing Previously authenticated publication mappings.
   --  @param Selected_Task_Ids Optional task subset; empty selects every task.
   --  @param Existing_Only Adopt committed tasks without creating missing native work.
   --  @param Dry_Run Validate and translate without committing the harness transaction.
   --  @return Native task mappings and authorization behavior.
end Improve.Workflow_Publication;
