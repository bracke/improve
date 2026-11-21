with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Harness_States;
with Improve.Model;
with Improve.State;

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

   type Plan_Comparison is record
      Plan_Id       : UString;
      From_Revision : Positive := 1;
      To_Revision   : Positive := 1;
      Changed       : Boolean := False;
      Reasons       : Improve.Model.UString_Vectors.Vector;
   end record;
   --  Deterministic explanation of differences between two immutable plan revisions.
   --  @field Plan_Id Stable logical plan identity.
   --  @field From_Revision Earlier revision compared.
   --  @field To_Revision Later revision compared.
   --  @field Changed Whether any semantic or task-contract difference exists.
   --  @field Reasons Stable ordered human-readable change explanations.

   type Diagnostic_Status is (Diagnostic_Pass, Diagnostic_Warning, Diagnostic_Fail);
   --  Outcome of one read-only diagnostic check.
   --  @enum Diagnostic_Pass Required local precondition is satisfied.
   --  @enum Diagnostic_Warning Optional local state is unavailable.
   --  @enum Diagnostic_Fail Required local state is invalid or unavailable.

   type Diagnostic_Check is record
      Name   : UString;
      Status : Diagnostic_Status := Diagnostic_Pass;
      Detail : UString;
   end record;
   --  One read-only environment or state diagnostic.
   --  @field Name Stable diagnostic check name.
   --  @field Status Check disposition.
   --  @field Detail Bounded diagnostic explanation.

   package Diagnostic_Vectors is new Ada.Containers.Vectors (Positive, Diagnostic_Check);
   --  Ordered diagnostic checks.

   type Diagnostic_Report is record
      Checks  : Diagnostic_Vectors.Vector;
      Healthy : Boolean := True;
   end record;
   --  Complete read-only diagnostic report.
   --  @field Checks Ordered local checks.
   --  @field Healthy Whether every required check passed.

   type Audit_Bundle is record
      Plan     : Improve.Model.Plan_Revision;
      Approved : Boolean := False;
      History  : Improve.State.Inspection_History;
   end record;
   --  Deterministic read-only evidence bundle for one exact immutable plan revision.
   --  @field Plan Selected plan and complete provenance.
   --  @field Approved Whether the exact revision fingerprint is durably approved.
   --  @field History Publication mappings and verification evidence visible for the selected revision.

   type Published_Task is record
      Improve_Id : UString;
      Harness_Id : UString;
      Origin     : UString;
      Contract   : UString;
      State      : UString;
      Core_State : Improve.Harness_States.State;
      Recovered  : Boolean := False;
   end record;
   --  Native publication mapping returned by an application operation.
   --  @field Improve_Id Logical remediation task identity.
   --  @field Harness_Id Native model_runner task identity.
   --  @field Origin Authenticated Improve publication origin.
   --  @field Contract Dependency-qualified execution contract.
   --  @field State Raw harness-owned runtime state.
   --  @field Core_State Normalized model_runner core state.
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
