with Improve.Model;
with Improve.Config;
with Improve.Results;
with Improve.Storage;
with Ada_Quality.Reporting;

--  Publication authorization, journaling, and native task creation.
package Improve.Operations.Publication is
   --  Complete publication use case independent of presentation.

   type Result is record
      Plan      : Improve.Model.Plan_Revision;
      Published : Improve.Results.Publication_Result;
   end record;
   --  Plan and native task mappings produced by publication.
   --  @field Plan Exact immutable plan revision that was published.
   --  @field Published Created or safely adopted native task mappings.

   function Run
     (State_Path       : String;
      Quality_Path     : String;
      Plan_Id          : String;
      Selected_Task_Id : String;
      Task_Kind        : String;
      Dry_Run          : Boolean;
      Limits           : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits  : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits) return Result;
   --  Validate approval and source/evidence identity, journal the operation,
   --  publish through one native harness transaction, and persist mappings.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Plan_Id Stable plan identity, optionally with an exact revision.
   --  @param Selected_Task_Id One task to publish, or empty for the plan.
   --  @param Task_Kind Configured harness task kind or `auto`.
   --  @param Dry_Run Whether to validate without changing either writable store.
   --  @param Limits Hard persistence and history limits.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @param Evidence_Limits Shared quality evidence and source identity limits.
   --  @return Exact plan and resulting native publication mappings.
end Improve.Operations.Publication;
