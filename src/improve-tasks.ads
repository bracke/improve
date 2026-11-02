with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Storage;

--  Deterministic read models over Improve plans and cached harness state.
package Improve.Tasks is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   type Operational_Status is
     (Proposed, Published, In_Progress, Awaiting_Verification, Verified, Blocked, Failed, Cancelled, Rejected,
      Partially_Resolved, Still_Failing, Inconclusive, Regressed, Superseded);

   function Image (Value : Operational_Status) return String;
   --  Return the stable lowercase status spelling.

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

   package View_Vectors is new Ada.Containers.Vectors (Positive, Task_View);

   function Build
     (Plan          : Improve.Model.Plan_Revision;
      Publications  : Improve.Storage.Publication_Vectors.Vector;
      Verifications : Improve.Storage.Verification_Vectors.Vector) return View_Vectors.Vector;
   --  Build one stable view per task in plan order.

   procedure Sort (Values : in out View_Vectors.Vector);
   --  Sort by project, plan, and Improve task identity.

   function Valid_Filter (Value : String) return Boolean;
   --  Whether Value is `all`, `unresolved`, or a stable status spelling.

   function Matches (Value : Task_View; Filter : String) return Boolean;
   --  Apply an already validated status filter.

   type Finding_Summary is record
      Resolved       : Natural := 0;
      Outstanding    : Natural := 0;
      Not_Measurable : Natural := 0;
      Regressed      : Natural := 0;
      Superseded     : Natural := 0;
   end record;

   function Findings
     (Plan  : Improve.Model.Plan_Revision;
      Views : View_Vectors.Vector) return Finding_Summary;
   --  Summarize the disposition of each baseline finding in one plan.

   type Project_Status is record
      Project_Id    : Positive;
      Project       : UString;
      Baseline_Run  : Natural := 0;
      Latest_Run    : Natural := 0;
      Plan_Count    : Natural := 0;
      Tasks         : View_Vectors.Vector;
      Findings      : Finding_Summary;
   end record;

   package Status_Vectors is new Ada.Containers.Vectors (Positive, Project_Status);
end Improve.Tasks;
