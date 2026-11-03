with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Storage;

--  Native model_runner task publication adapter.
package Improve.Workflow is
   --  Transactional adapter to native model_runner tasks and state.

   type Published_Task is record
      Improve_Id : Ada.Strings.Unbounded.Unbounded_String;
      Harness_Id : Ada.Strings.Unbounded.Unbounded_String;
      Origin     : Ada.Strings.Unbounded.Unbounded_String;
      Contract   : Ada.Strings.Unbounded.Unbounded_String;
      State      : Ada.Strings.Unbounded.Unbounded_String;
      Recovered  : Boolean := False;
   end record;
   --  Verified native publication mapping.
   --  @field Improve_Id Stable Improve task identity.
   --  @field Harness_Id Native model_runner task identity.
   --  @field Origin Stable authenticated Improve provenance.
   --  @field Contract Complete execution contract represented by the native task.
   --  @field State Harness-owned runtime state.
   --  @field Recovered Whether an existing task was safely adopted.

   package Published_Vectors is new Ada.Containers.Vectors (Positive, Published_Task);
   --  Ordered publication mappings.

   type Publication_Result is record
      Task_Kind : Ada.Strings.Unbounded.Unbounded_String;
      Tasks     : Published_Vectors.Vector;
   end record;
   --  Result of native task translation and publication.
   --  @field Task_Kind Resolved compatible harness task kind.
   --  @field Tasks Published or safely recovered task mappings.

   function Publish
     (Project_Directory : String;
      Plan              : Improve.Model.Plan_Revision;
      Requested_Kind    : String;
      Existing          : Improve.Storage.Publication_Vectors.Vector :=
        Improve.Storage.Publication_Vectors.Empty_Vector;
      Selected_Task_Ids : Improve.Model.UString_Vectors.Vector :=
        Improve.Model.UString_Vectors.Empty_Vector;
      Existing_Only     : Boolean := False;
      Dry_Run           : Boolean := False) return Publication_Result;
   --  Validate and publish native candidate tasks in one harness transaction.
   --  Stable origins recover a prior harness commit without duplicating tasks.
   --  A changed contract retires safe predecessors in the same transaction,
   --  preserves completed history, and rejects active execution replacement.
   --  @param Project_Directory Initialized model_runner project directory.
   --  @param Plan Immutable plan revision to publish.
   --  @param Requested_Kind Configured task kind or `auto`.
   --  @param Existing Previously verified publication mappings for reused logical tasks.
   --  @param Selected_Task_Ids Tasks to publish, or empty for the complete plan.
   --  @param Existing_Only Return provenance-verified existing tasks without creating missing work.
   --  @param Dry_Run Whether to validate without changing harness state.
   --  @return Resolved task kind and native mappings.

   function Reconcile
     (Project_Directory : String;
      Published         : Published_Vectors.Vector) return Published_Vectors.Vector;
   --  Read current harness-owned task states after validating each persisted
   --  mapping's identity and Improve provenance. No harness state is changed.
   --  @param Project_Directory Initialized model_runner project directory.
   --  @param Published Persisted publication mappings.
   --  @return Mappings with reconciled harness-owned states.
end Improve.Workflow;
