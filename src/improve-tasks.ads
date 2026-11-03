with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Storage;

--  Deterministic read models over Improve plans and cached harness state.
package Improve.Tasks is
   --  Stable inspection views derived from immutable plans, publication mappings, and verification evidence.

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Shared owned string representation.

   type Operational_Status is
     (Proposed, Published, In_Progress, Awaiting_Verification, Verified, Blocked, Failed, Cancelled, Rejected,
      Partially_Resolved, Still_Failing, Inconclusive, Regressed, Superseded);
   --  Improve inspection status, distinct from harness-owned runtime state.
   --  @enum Proposed Not yet published to model_runner.
   --  @enum Published Native candidate exists but has not started.
   --  @enum In_Progress Harness execution is active.
   --  @enum Awaiting_Verification Harness work completed but quality evidence is absent.
   --  @enum Verified Independent evidence satisfies every mandatory criterion.
   --  @enum Blocked Harness execution is blocked.
   --  @enum Failed Harness execution failed.
   --  @enum Cancelled Harness execution was cancelled.
   --  @enum Rejected Harness candidate was rejected.
   --  @enum Partially_Resolved Some mandatory quality criteria are satisfied.
   --  @enum Still_Failing Mandatory quality criteria remain unsatisfied.
   --  @enum Inconclusive Current evidence cannot establish success or failure.
   --  @enum Regressed A previously resolved quality condition returned.
   --  @enum Superseded Newer valid work replaced the task.

   function Image (Value : Operational_Status) return String;
   --  Return the stable lowercase status spelling.
   --  @param Value Status to render.
   --  @return Stable machine-readable spelling.

   type Task_View is record
      Project_Id     : Positive;
      Project        : UString;
      Plan_Id        : UString;
      Improve_Id     : UString;
      Harness_Id     : UString;
      Title          : UString;
      Harness_State  : UString;
      Quality        : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Has_Verification : Boolean := False;
      Status         : Operational_Status := Proposed;
   end record;
   --  Joined inspection view for one Improve task.
   --  @field Project_Id Target project identity.
   --  @field Project Target project name.
   --  @field Plan_Id Stable plan identity.
   --  @field Improve_Id Stable Improve task identity.
   --  @field Harness_Id Native task identity, when published.
   --  @field Title Task title.
   --  @field Harness_State Cached harness-owned state.
   --  @field Quality Latest independent quality outcome.
   --  @field Has_Verification Whether quality evidence has been recorded.
   --  @field Status Derived inspection status.

   package View_Vectors is new Ada.Containers.Vectors (Positive, Task_View);
   --  Ordered task inspection views.

   function Build
     (Plan          : Improve.Model.Plan_Revision;
      Publications  : Improve.Storage.Publication_Vectors.Vector;
      Verifications : Improve.Storage.Verification_Vectors.Vector) return View_Vectors.Vector;
   --  Build one stable view per task in plan order.
   --  @param Plan Immutable plan revision.
   --  @param Publications Publication mappings for the plan.
   --  @param Verifications Historical verification evidence.
   --  @return Joined task views.

   procedure Sort (Values : in out View_Vectors.Vector);
   --  Sort by project, plan, and Improve task identity.
   --  @param Values Views to sort in place.

   function Valid_Filter (Value : String) return Boolean;
   --  Whether Value is `all`, `unresolved`, or a stable status spelling.
   --  @param Value Candidate filter.
   --  @return True when the filter is recognized.

   function Matches (Value : Task_View; Filter : String) return Boolean;
   --  Apply an already validated status filter.
   --  @param Value Task view to test.
   --  @param Filter Validated status filter.
   --  @return True when the task matches.

   type Finding_Summary is record
      Resolved       : Natural := 0;
      Outstanding    : Natural := 0;
      Not_Measurable : Natural := 0;
      Regressed      : Natural := 0;
      Superseded     : Natural := 0;
   end record;
   --  Aggregate baseline finding disposition.
   --  @field Resolved Findings independently verified as resolved.
   --  @field Outstanding Findings that remain unresolved.
   --  @field Not_Measurable Findings whose current evidence is inconclusive.
   --  @field Regressed Findings that returned after resolution.
   --  @field Superseded Findings replaced by newer valid work.

   function Findings
     (Plan  : Improve.Model.Plan_Revision;
      Views : View_Vectors.Vector) return Finding_Summary;
   --  Summarize the disposition of each baseline finding in one plan.
   --  @param Plan Immutable plan revision.
   --  @param Views Task views derived for the plan.
   --  @return Aggregate finding disposition.

   type Project_Status is record
      Project_Id    : Positive;
      Project       : UString;
      Baseline_Run  : Natural := 0;
      Latest_Run    : Natural := 0;
      Plan_Count    : Natural := 0;
      Plan_Quality  : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Has_Plan_Verification : Boolean := False;
      Plan_Verification_Run : Natural := 0;
      Project_Quality : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Has_Project_Verification : Boolean := False;
      Project_Verification_Run : Natural := 0;
      Tasks         : View_Vectors.Vector;
      Findings      : Finding_Summary;
   end record;
   --  Project-level remediation summary.
   --  @field Project_Id Target project identity.
   --  @field Project Target project name.
   --  @field Baseline_Run Assessment that generated the plan.
   --  @field Latest_Run Latest observed completed assessment.
   --  @field Plan_Count Number of remediation plans.
   --  @field Plan_Quality Latest complete plan-level verification outcome.
   --  @field Has_Plan_Verification Whether a complete plan outcome has been recorded.
   --  @field Plan_Verification_Run Assessment evaluated by Plan_Quality.
   --  @field Project_Quality Latest independently persisted project-level outcome.
   --  @field Has_Project_Verification Whether a project-level outcome has been recorded.
   --  @field Project_Verification_Run Assessment evaluated by Project_Quality.
   --  @field Tasks Joined task views.
   --  @field Findings Aggregate finding disposition.

   package Status_Vectors is new Ada.Containers.Vectors (Positive, Project_Status);
   --  Ordered project status summaries.
end Improve.Tasks;
