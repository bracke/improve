with Improve.Config;
with Improve.Model;
with Improve.Verification;

--  Assessment-scoped verification selection and persistence.
package Improve.Operations.Verification is
   --  Complete verification use case independent of presentation.

   type Result is record
      Plan   : Improve.Model.Plan_Revision;
      Report : Improve.Verification.Report;
   end record;
   --  Exact plan and assessment comparison produced by verification.
   --  @field Plan Immutable plan revision whose contract was evaluated.
   --  @field Report Scope-aware task, plan, and project quality outcomes.

   function Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Task_Id          : String;
      Revision         : Natural;
      Run_Id           : Natural;
      Settings         : Improve.Config.Settings) return Result;
   --  Select an exact historical contract, compare completed evidence, and
   --  persist idempotent scope-qualified verification records.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Project_Selector Project identity or unique project name.
   --  @param Task_Id One task to evaluate, or empty for the plan and project.
   --  @param Revision Exact plan revision, or zero for the latest revision.
   --  @param Run_Id Completed assessment identity, or zero for the latest.
   --  @param Settings Verification comparability policy and limits.
   --  @return Exact plan and scope-aware verification report.
end Improve.Operations.Verification;
