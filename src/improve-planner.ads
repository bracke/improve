with Ada_Quality.Types;
with Improve.Model;
with Improve.Source;

--  Deterministic transformation of normalized evidence into bounded work.
package Improve.Planner is
   --  Evidence-driven grouping, decomposition, prioritization, and task specification.

   Planner_Version : constant String := "deterministic-v2";
   --  Stable planner algorithm version included in plan provenance.

   type Policy is record
      Minimum_Severity          : Ada_Quality.Types.Severity := Ada_Quality.Types.Low;
      Maximum_Tasks             : Positive := 100;
      Maximum_Findings_Per_Task : Positive := 50;
      Allow_Investigation       : Boolean := True;
      Require_Review            : Boolean := True;
      Maximum_Source_File_Bytes : Positive := 16_777_216;
      Maximum_Source_Total_Bytes : Positive := 268_435_456;
   end record;
   --  Planning-only policy, independent of configuration and presentation.
   --  @field Minimum_Severity Lowest non-indicator-level finding accepted by the planner.
   --  @field Maximum_Tasks Maximum tasks generated for one plan.
   --  @field Maximum_Findings_Per_Task Maximum evidence references grouped into one task.
   --  @field Allow_Investigation Whether investigation or diagnostic findings are accepted.
   --  @field Require_Review Whether generated task specifications require approval.
   --  @field Maximum_Source_File_Bytes Maximum source bytes read from one file.
   --  @field Maximum_Source_Total_Bytes Maximum source bytes read for one identity.

   function Generate
     (Selected : Improve.Source.Selection;
      Findings : Improve.Model.Finding_Vectors.Vector;
      Settings : Policy;
      Working_Source_Id : String := "") return Improve.Model.Plan_Revision;
   --  Group related evidence, split oversized groups, and generate explicit task
   --  specifications. Equal inputs and planner configuration produce the same
   --  plan fingerprint and task definitions.
   --  @param Selected Completed assessment and provenance.
   --  @param Findings Normalized eligible findings.
   --  @param Settings Validated planning limits and policy.
   --  @param Working_Source_Id Precomputed working-tree identity, or empty to calculate it.
   --  @return Deterministic immutable draft revision.
   --  @exception Data_Error Evidence cannot form a safe plan or limits are exceeded.
end Improve.Planner;
