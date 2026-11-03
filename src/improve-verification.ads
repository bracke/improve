with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Config;
with Improve.Model;
with Improve.Source;

--  Independent comparison of remediation intent with completed measurements.
package Improve.Verification is
   --  Evidence-based quality verification independent of harness execution state.

   type Task_Result is record
      Task_Id     : Ada.Strings.Unbounded.Unbounded_String;
      Outcome     : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Matched     : Natural := 0;
      Total       : Natural := 0;
      Explanation : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Verification conclusion for one Improve task.
   --  @field Task_Id Stable Improve task identity.
   --  @field Outcome Independent quality outcome.
   --  @field Matched Associated findings matched in current evidence.
   --  @field Total Mandatory associated findings.
   --  @field Explanation Evidence-based conclusion.

   package Result_Vectors is new Ada.Containers.Vectors (Positive, Task_Result);
   --  Ordered task verification results.

   function Contract_Fingerprint (Item : Improve.Model.Task_Specification) return String;
   --  Identify the complete immutable task definition and acceptance contract.
   --  @param Item Task definition to identify.
   --  @return Stable deterministic contract fingerprint.

   type Report is record
      Plan_Id          : Ada.Strings.Unbounded.Unbounded_String;
      Baseline_Run     : Positive;
      Verification_Run : Positive;
      Outcome          : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Plan_Outcome     : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Project_Outcome  : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Comparable       : Boolean := False;
      New_Critical     : Natural := 0;
      Explanation      : Ada.Strings.Unbounded.Unbounded_String;
      Tasks            : Result_Vectors.Vector;
   end record;
   --  Verification report for a plan or selected task.
   --  @field Plan_Id Stable plan identity.
   --  @field Baseline_Run Original assessment identity.
   --  @field Verification_Run Current completed assessment identity.
   --  @field Outcome Aggregate quality outcome.
   --  @field Plan_Outcome Complete plan outcome, or unverified for task-only evaluation.
   --  @field Project_Outcome Complete assessment outcome, or unverified for task-only evaluation.
   --  @field Comparable Whether the evidence can establish an outcome.
   --  @field New_Critical New unrelated critical findings.
   --  @field Explanation Comparability and outcome explanation.
   --  @field Tasks Per-task conclusions.

   function Evaluate
     (Plan     : Improve.Model.Plan_Revision;
      Current  : Improve.Source.Selection;
      Settings : Improve.Config.Settings;
      Task_Id  : String := "";
      Previously_Verified : Improve.Model.UString_Vectors.Vector :=
        Improve.Model.UString_Vectors.Empty_Vector) return Report;
   --  Evaluate existing completed evidence without running a measurement.
   --  @param Plan Immutable originating plan revision.
   --  @param Current Current completed assessment selection.
   --  @param Settings Verification policy.
   --  @param Task_Id Optional Improve task identity filter.
   --  @param Previously_Verified Task identities previously verified successfully.
   --  @return Independent verification report.
end Improve.Verification;
