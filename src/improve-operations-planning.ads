with Improve.Config;
with Improve.Model;
with Improve.State;
with Improve.Storage;
with Ada_Quality.Reporting;

--  Deterministic planning and immutable plan-history use cases.
package Improve.Operations.Planning is
   --  Planning orchestration independent of CLI and JSON presentation.

   type Generation_Result is record
      Plan     : Improve.Model.Plan_Revision;
      Existing : Boolean := False;
   end record;
   --  Generated plan and whether persistence reused identical content.
   --  @field Plan Generated draft or persisted immutable plan revision.
   --  @field Existing True when persistence reused identical plan content.

   function Generate
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Run_Id           : Natural;
      Settings         : Improve.Config.Settings;
      Dry_Run          : Boolean) return Generation_Result;
   --  Generate a deterministic plan and persist it unless Dry_Run is true.
   --  @param State_Path Improve state database path.
   --  @param Quality_Path Read-only Ada Quality database path.
   --  @param Project_Selector Project identity or unique name.
   --  @param Run_Id Explicit completed run, or zero for the latest.
   --  @param Settings Effective deterministic planner settings.
   --  @param Dry_Run Whether to return a draft without persistence.
   --  @return Generated plan and persistence reuse state.

   function Load
     (State_Path : String;
      Plan_Id    : String;
      Revision   : Natural := 0;
      Limits     : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits)
      return Improve.Model.Plan_Revision;
   --  Load the latest or an exact immutable plan revision.
   --  @param State_Path Existing Improve state database path.
   --  @param Plan_Id Stable plan identity.
   --  @param Revision Exact revision, or zero for the latest.
   --  @param Limits Hard persistence reconstruction limits.
   --  @return Selected immutable plan revision.

   function List
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Maximum_Items    : Positive := Improve.Storage.Default_Query_Maximum;
      Limits           : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits  : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits)
      return Improve.State.Summary_Vectors.Vector;
   --  List stored plans for one database-qualified project.
   --  @param State_Path Existing Improve state database path.
   --  @param Quality_Path Read-only Ada Quality database path.
   --  @param Project_Selector Project identity or unique name.
   --  @param Maximum_Items Maximum plan summaries to materialize.
   --  @param Limits Hard persistence reconstruction limits.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @param Evidence_Limits Shared quality evidence and source identity limits.
   --  @return Latest stored plan summaries for the exact project identity.

   function Approve
     (State_Path : String;
      Plan_Id    : String;
      Limits     : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits)
      return Improve.Model.Plan_Revision;
   --  Approve the latest immutable revision and return it.
   --  @param State_Path Existing Improve state database path.
   --  @param Plan_Id Stable plan identity.
   --  @param Limits Hard persistence reconstruction limits.
   --  @return Exact approved immutable plan revision.
end Improve.Operations.Planning;
