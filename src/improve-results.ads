with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Model;

--  Storage-independent application results shared by use cases and output adapters.
package Improve.Results is
   --  Domain-facing read models with no dependency on the persistence adapter.

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Owned UTF-8 application-result text.

   type Project_Record is record
      Id      : Positive;
      Path    : UString;
      Enabled : Boolean := True;
      Removed : Boolean := False;
   end record;
   --  Presentation-neutral registered project.
   --  @field Id Stable Ada Quality project identity.
   --  @field Path Registered project path.
   --  @field Enabled Whether assessment is enabled.
   --  @field Removed Whether the project has been removed.

   package Project_Vectors is new Ada.Containers.Vectors (Positive, Project_Record);
   --  Ordered registered projects.

   type Project_List is record
      Values   : Project_Vectors.Vector;
      Snapshot : UString;
   end record;
   --  Registered projects and their reporting snapshot identity.
   --  @field Values Ordered registered projects.
   --  @field Snapshot Reporting snapshot identity.

   type Finding_List is record
      Project_Id    : Positive;
      Project       : UString;
      Run_Id        : Positive;
      Assessment_Id : UString;
      Snapshot_Id   : UString;
      Values        : Improve.Model.Finding_Vectors.Vector;
   end record;
   --  Presentation-neutral normalized findings and assessment provenance.
   --  @field Project_Id Stable Ada Quality project identity.
   --  @field Project Project display name.
   --  @field Run_Id Selected completed assessment run.
   --  @field Assessment_Id Complete assessment evidence identity.
   --  @field Snapshot_Id Reporting snapshot identity.
   --  @field Values Normalized remediation findings.

   type Published_Task is record
      Improve_Id : UString;
      Harness_Id : UString;
      Origin     : UString;
      Contract   : UString;
      State      : UString;
      Recovered  : Boolean := False;
   end record;
   --  Native publication mapping returned by an application operation.
   --  @field Improve_Id Logical remediation task identity.
   --  @field Harness_Id Native model_runner task identity.
   --  @field Origin Authenticated Improve publication origin.
   --  @field Contract Dependency-qualified execution contract.
   --  @field State Harness-owned runtime state.
   --  @field Recovered Whether an existing native task was reused.

   package Published_Task_Vectors is new Ada.Containers.Vectors (Positive, Published_Task);
   --  Ordered publication-operation results.

   type Publication_Result is record
      Task_Kind : UString;
      Tasks     : Published_Task_Vectors.Vector;
   end record;
   --  Presentation-neutral native publication result.
   --  @field Task_Kind Resolved native task kind.
   --  @field Tasks Ordered publication mappings.

   type Verification_Task_Result is record
      Task_Id     : UString;
      Outcome     : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Matched     : Natural := 0;
      Total       : Natural := 0;
      Explanation : UString;
   end record;
   --  Presentation-neutral verification conclusion for one task.
   --  @field Task_Id Logical remediation task identity.
   --  @field Outcome Independent quality outcome.
   --  @field Matched Findings matched against the acceptance contract.
   --  @field Total Findings required by the acceptance contract.
   --  @field Explanation Evidence-based conclusion.

   package Verification_Task_Vectors is new Ada.Containers.Vectors (Positive, Verification_Task_Result);
   --  Ordered task verification conclusions.

   type Verification_Report is record
      Plan_Id          : UString;
      Baseline_Run     : Positive;
      Verification_Run : Positive;
      Outcome          : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Plan_Outcome     : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Project_Outcome  : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Comparable       : Boolean := False;
      New_Critical     : Natural := 0;
      Explanation      : UString;
      Tasks            : Verification_Task_Vectors.Vector;
   end record;
   --  Presentation-neutral scope-aware verification report.
   --  @field Plan_Id Evaluated logical plan identity.
   --  @field Baseline_Run Original completed assessment run.
   --  @field Verification_Run Current completed assessment run.
   --  @field Outcome Command-level verification outcome.
   --  @field Plan_Outcome Plan acceptance-contract outcome.
   --  @field Project_Outcome Project regression outcome.
   --  @field Comparable Whether baseline and current evidence are comparable.
   --  @field New_Critical Newly introduced critical findings.
   --  @field Explanation Evidence-based aggregate conclusion.
   --  @field Tasks Ordered task-level conclusions.

   type Recovery_Result is record
      Operations_Recovered : Natural := 0;
      Tasks_Recovered      : Natural := 0;
   end record;
   --  Work recovered by one bounded invocation.
   --  @field Operations_Recovered Interrupted journal operations completed.
   --  @field Tasks_Recovered Native task mappings recovered.

end Improve.Results;
