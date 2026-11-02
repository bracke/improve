with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Model;

--  Native model_runner task publication adapter.
package Improve.Workflow is
   type Published_Task is record
      Improve_Id : Ada.Strings.Unbounded.Unbounded_String;
      Harness_Id : Ada.Strings.Unbounded.Unbounded_String;
      Origin     : Ada.Strings.Unbounded.Unbounded_String;
      State      : Ada.Strings.Unbounded.Unbounded_String;
      Recovered  : Boolean := False;
   end record;

   package Published_Vectors is new Ada.Containers.Vectors (Positive, Published_Task);

   type Publication_Result is record
      Task_Kind : Ada.Strings.Unbounded.Unbounded_String;
      Tasks     : Published_Vectors.Vector;
   end record;

   function Publish
     (Project_Directory : String;
      Plan              : Improve.Model.Plan_Revision;
      Requested_Kind    : String;
      Dry_Run           : Boolean := False) return Publication_Result;
   --  Validate and publish native candidate tasks in one harness transaction.
   --  Stable origins recover a prior harness commit without duplicating tasks.

   function Reconcile
     (Project_Directory : String;
      Published         : Published_Vectors.Vector) return Published_Vectors.Vector;
   --  Read current harness-owned task states after validating each persisted
   --  mapping's identity and Improve provenance. No harness state is changed.
end Improve.Workflow;
