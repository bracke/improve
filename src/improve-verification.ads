with Improve.Model;
with Improve.Results;
with Improve.Source;

--  Independent comparison of remediation intent with completed measurements.
package Improve.Verification is
   --  Evidence-based quality verification independent of harness execution state.

   type Policy is record
      Maximum_Assessment_Findings       : Positive := 10_000;
      Maximum_Normalized_Finding_Bytes  : Positive := 16_777_216;
      Require_Fresh_Measurement         : Boolean := True;
      Require_Same_Policy               : Boolean := True;
      Require_Same_Toolchain            : Boolean := False;
      Require_No_New_Critical_Findings  : Boolean := True;
   end record;
   --  Verification-only policy, independent of configuration and presentation.
   --  @field Maximum_Assessment_Findings Maximum findings normalized from current evidence.
   --  @field Maximum_Normalized_Finding_Bytes Maximum normalized finding bytes.
   --  @field Require_Fresh_Measurement Whether verification requires a newer assessment.
   --  @field Require_Same_Policy Whether quality policy identity must match.
   --  @field Require_Same_Toolchain Whether toolchain identity must match.
   --  @field Require_No_New_Critical_Findings Whether unrelated critical findings cause regression.

   subtype Task_Result is Improve.Results.Verification_Task_Result;
   --  Application-result verification conclusion for one Improve task.

   subtype Report is Improve.Results.Verification_Report;
   --  Application-result verification report for a plan or selected task.

   function Evaluate
     (Plan     : Improve.Model.Plan_Revision;
      Current  : Improve.Source.Selection;
      Settings : Policy;
      Task_Id  : String := "";
      Previously_Verified : Improve.Model.UString_Vectors.Vector :=
        Improve.Model.UString_Vectors.Empty_Vector) return Report;
   --  Evaluate existing completed evidence without running a measurement.
   --  @param Plan Immutable originating plan revision.
   --  @param Current Current completed assessment selection.
   --  @param Settings Verification evidence limits and comparability policy.
   --  @param Task_Id Optional Improve task identity filter.
   --  @param Previously_Verified Task identities previously verified successfully.
   --  @return Independent verification report.
end Improve.Verification;
