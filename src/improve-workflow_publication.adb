with Ada.Containers;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Model_Runner.Errors;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;
with Model_Runner.Framework.Transitions;

package body Improve.Workflow_Publication is
   use Ada.Strings.Unbounded;
   use Improve.Workflow;
   use type Ada.Containers.Count_Type;

   package Errors renames Model_Runner.Errors;
   package Records renames Model_Runner.Framework.Records;
   package Stores renames Model_Runner.Framework.Stores;
   package Tasks renames Model_Runner.Framework.Tasks;
   package Transitions renames Model_Runner.Framework.Transitions;

   package Native_Origin_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Unbounded_String,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package String_Index_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Positive,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Index_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Positive);

   function Detail (Status : Errors.Error_Info) return String is
      Name   : constant String := Errors.Text_Of (Status, "name");
      Reason : constant String := Errors.Text_Of (Status, "detail");
   begin
      return Errors.Diagnostic_Code (Status.Code) &
        (if Name = "" then "" else " " & Name) &
        (if Reason = "" then "" else ": " & Reason);
   end Detail;

   procedure Require_Ok (Status : Errors.Error_Info; Context : String) is
   begin
      if Errors.Is_Error (Status) then raise Data_Error with Context & ": " & Detail (Status); end if;
   end Require_Ok;

   function Resolve_Kind (Store : Stores.Store; Requested : String) return String is
      Kinds : constant Model_Runner.Framework.Name_Lists.Vector := Tasks.Kinds (Store);
   begin
      if Requested /= "auto" then
         if not Kinds.Contains (Requested) then
            raise Data_Error with "configured remediation task kind is not available: " & Requested;
         end if;
         return Requested;
      elsif Kinds.Length = 1 then
         return Kinds.First_Element;
      elsif Kinds.Is_Empty then
         raise Data_Error with "target project defines no task kind";
      else
         raise Data_Error with "task_kind=auto is ambiguous; configure one of the target project's task kinds";
      end if;
   end Resolve_Kind;

   function Origin_Of
     (Plan : Improve.Model.Plan_Revision;
      Spec : Improve.Model.Task_Specification;
      Contract : String) return String is
     ("improve:" & Stable_Digest (To_String (Plan.Project.Path)) & ":task:" & To_String (Spec.Id) &
      ":contract:" & Contract);

   function Harness_Priority (Value : Improve.Model.Priority) return String is
     (case Value is
         when Improve.Model.Critical_Priority => "100",
         when Improve.Model.High_Priority => "75",
         when Improve.Model.Normal_Priority => "50",
         when Improve.Model.Low_Priority => "25");

   function Join (Values : Improve.Model.UString_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      for Value of Values loop
         if Length (Result) > 0 then Append (Result, ", "); end if;
         Append (Result, Value);
      end loop;
      return To_String (Result);
   end Join;

   function Native_Notes
     (Spec         : Improve.Model.Task_Specification;
      Binding      : String;
      Predecessors : Improve.Model.UString_Vectors.Vector) return String is
     ("Improve task: " & To_String (Spec.Id) & ASCII.LF &
      "Contract: " & Improve.Model.Task_Contract_Fingerprint (Spec) & ASCII.LF &
      "Dependency binding: " & Binding & ASCII.LF &
      (if Predecessors.Is_Empty then "" else "Supersedes: " & Join (Predecessors) & ASCII.LF) &
      "Goal: " & To_String (Spec.Goal) & ASCII.LF &
      "Problem: " & To_String (Spec.Problem) & ASCII.LF &
      "Evidence:" & ASCII.LF & To_String (Spec.Evidence) & ASCII.LF &
      "Relevant files: " & Join (Spec.Relevant_Files) & ASCII.LF &
      "Scope: " & To_String (Spec.Scope) & ASCII.LF &
      "Out of scope: " & To_String (Spec.Out_Of_Scope) & ASCII.LF &
      "Requirements: " & To_String (Spec.Requirements) & ASCII.LF &
      "Verification: " & To_String (Spec.Verification));

   procedure Require_Compatible_Definition
     (Value  : Records.Item;
      Spec   : Improve.Model.Task_Specification;
      Kind   : String;
      Origin : String;
      Binding : String;
      Predecessors : Improve.Model.UString_Vectors.Vector) is
   begin
      if Records.Get (Value, "created_by") /= "improve" or else Records.Get (Value, "origin") /= Origin then
         raise Data_Error with "native task provenance does not match Improve publication identity";
      end if;
      if Records.Get (Value, "title") /= To_String (Spec.Title) or else
        Records.Get (Value, "kind") /= Kind or else
        Records.Get (Value, "priority") /= Harness_Priority (Spec.Task_Priority) or else
        Records.Get (Value, "acceptance") /= To_String (Spec.Acceptance) or else
        Records.Get (Value, "notes") /= Native_Notes (Spec, Binding, Predecessors)
      then
         raise Data_Error with
           "native task definition differs from the complete Improve contract for " & To_String (Spec.Id);
      end if;
   end Require_Compatible_Definition;

   type Prepared_Publication is record
      Selected  : Improve.Model.Task_Vectors.Vector;
      Contracts : Improve.Model.Task_Contract_Binding_Vectors.Vector;
   end record;

   function Build_Preflight
     (Plan              : Improve.Model.Plan_Revision;
      Selected_Task_Ids : Improve.Model.UString_Vectors.Vector) return Prepared_Publication is
      Result : Prepared_Publication;
   begin
      for Task_Id of Selected_Task_Ids loop
         if (for all Spec of Plan.Tasks => Spec.Id /= Task_Id) then
            raise Data_Error with "publication selection references unknown task " & To_String (Task_Id);
         end if;
      end loop;
      for Spec of Plan.Tasks loop
         if Selected_Task_Ids.Is_Empty or else Selected_Task_Ids.Contains (Spec.Id) then
            Result.Selected.Append (Spec);
         end if;
      end loop;
      if Result.Selected.Is_Empty then
         raise Argument_Error with "publication selection has no tasks";
      end if;
      Result.Contracts := Improve.Model.Effective_Task_Contracts (Plan);
      return Result;
   end Build_Preflight;

   function Execute
     (Project_Directory : String;
      Plan              : Improve.Model.Plan_Revision;
      Requested_Kind    : String;
      Existing          : Improve.Storage.Publication_Vectors.Vector :=
        Improve.Storage.Publication_Vectors.Empty_Vector;
      Selected_Task_Ids : Improve.Model.UString_Vectors.Vector :=
        Improve.Model.UString_Vectors.Empty_Vector;
      Existing_Only     : Boolean := False;
      Dry_Run           : Boolean := False) return Publication_Result is separate;
end Improve.Workflow_Publication;
