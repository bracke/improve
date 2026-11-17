with Improve.Model;
with Improve.Results;
with Improve.State;

--  Native model_runner task publication adapter.
package Improve.Workflow is
   --  Transactional adapter to native model_runner tasks and state.

   subtype Published_Task is Improve.Results.Published_Task;
   --  Storage-independent native publication mapping.

   subtype Publication_Result is Improve.Results.Publication_Result;
   --  Storage-independent native publication result.

   function Publish
     (Project_Directory : String;
      Publication_Namespace : String;
      Plan              : Improve.Model.Plan_Revision;
      Requested_Kind    : String;
      Existing          : Improve.State.Publication_Vectors.Vector :=
        Improve.State.Publication_Vectors.Empty_Vector;
      Selected_Task_Ids : Improve.Model.UString_Vectors.Vector :=
        Improve.Model.UString_Vectors.Empty_Vector;
      Existing_Only     : Boolean := False;
      Dry_Run           : Boolean := False) return Publication_Result;
   --  Validate and publish native candidate tasks in one harness transaction.
   --  Stable origins recover a prior harness commit without duplicating tasks.
   --  A changed contract retires safe predecessors in the same transaction,
   --  preserves completed history, and rejects active execution replacement.
   --  Transitive dependency bindings replace safe published dependents with
   --  native edges to the replacement prerequisites; unsafe selective work
   --  is rejected before any harness change.
   --  @param Project_Directory Initialized model_runner project directory.
   --  @param Publication_Namespace Stable identity of the owning Improve state store.
   --  @param Plan Immutable plan revision to publish.
   --  @param Requested_Kind Configured task kind or `auto`.
   --  @param Existing Previously verified publication mappings for reused logical tasks.
   --  @param Selected_Task_Ids Tasks to publish, or empty for the complete plan.
   --  @param Existing_Only Return provenance-verified existing tasks without creating missing work.
   --  @param Dry_Run Whether to validate without changing harness state.
   --  @return Resolved task kind and native mappings.

end Improve.Workflow;
