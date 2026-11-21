with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve.Harness_States;
with Improve.Model;
with Improve.State;
with Improve.Tasks;

package body Improve_Tasks_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Tasks.Operational_Status;
   use type Improve.Tasks.Verification_Freshness;

   type Task_Case is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Task_Case;

   overriding procedure Run_Test (Item : in out Task_Case);

   overriding function Name (Item : Task_Case) return AUnit.Message_String is
     (AUnit.Format ("IMP_TASK_STATUS_MATRIX"));

   function Fixture return Improve.Model.Plan_Revision is
      Result  : Improve.Model.Plan_Revision;
      Finding : Improve.Model.Finding_Reference;
      Spec    : Improve.Model.Task_Specification;
   begin
      Result.Plan_Id := To_Unbounded_String ("PLAN-000001");
      Result.Revision := 1;
      Result.Fingerprint := To_Unbounded_String ("plan-contract");
      Result.Project :=
        (Id => 1, Name => To_Unbounded_String ("fixture"), Path => To_Unbounded_String ("/fixture"),
         Database_Id => To_Unbounded_String ("/quality.db"));
      Finding.Project_Id := 1;
      Finding.Run_Id := 1;
      Finding.Indicator := Ada_Quality.Types.SRC_04;
      Finding.Fingerprint := To_Unbounded_String ("finding-1");
      Result.Findings.Append (Finding);
      Spec.Id := To_Unbounded_String ("IMP-000001");
      Spec.Title := To_Unbounded_String ("Repair source hygiene");
      Spec.Category := To_Unbounded_String ("remediation");
      Spec.Goal := To_Unbounded_String ("Resolve the finding");
      Spec.Acceptance := To_Unbounded_String ("Source hygiene passes");
      Spec.Verification := To_Unbounded_String ("Remeasure SRC-04");
      Spec.Finding_Keys.Append (Finding.Fingerprint);
      Result.Tasks.Append (Spec);
      return Result;
   end Fixture;

   overriding procedure Run_Test (Item : in out Task_Case) is
      pragma Unreferenced (Item);
      Plan : constant Improve.Model.Plan_Revision := Fixture;
      Only : constant Improve.Model.Task_Specification := Plan.Tasks.First_Element;

      procedure Check
        (Harness_State : String;
         Expected      : Improve.Tasks.Operational_Status;
         Verified      : Boolean := False;
         Outcome       : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
         Current_Run   : Natural := 2) is
         Publications : Improve.State.Publication_Vectors.Vector;
         Evidence     : Improve.State.Verification_Vectors.Vector;
         Views        : Improve.Tasks.View_Vectors.Vector;
      begin
         if Harness_State /= "" then
            Publications.Append
              (Improve.State.Publication_Record'
                 (Improve_Task_Id => Only.Id,
                  Harness_Task_Id => To_Unbounded_String ("TASK-TEST-001"),
                  Origin          => To_Unbounded_String ("improve:test"),
                  Contract        => To_Unbounded_String
                    (Improve.Model.Effective_Task_Contract_Fingerprint (Plan, Only.Id)),
                  State           => To_Unbounded_String (Harness_State),
                  Core_State      => Improve.Harness_States.Parse_Core (Harness_State),
                  Plan_Revision   => Plan.Revision));
         end if;
         if Verified then
            Evidence.Append
              (Improve.State.Verification_Record'
                 (Scope                => Improve.Model.Task_Evaluation,
                  Task_Id              => Only.Id,
                  Plan_Revision        => Plan.Revision,
                  Contract_Fingerprint => To_Unbounded_String
                    (Improve.Model.Effective_Task_Contract_Fingerprint (Plan, Only.Id)),
                  Assessment_Id        => 2,
                  Outcome              => Outcome,
                  Comparable           => True,
                  Explanation          => To_Unbounded_String ("matrix")));
         end if;
         Views := Improve.Tasks.Build (Plan, Publications, Evidence, Current_Assessment => Current_Run);
         Assert
           (Improve.Tasks.Status (Views.First_Element) = Expected,
            "unexpected operational task status");
      end Check;
   begin
      declare
         Joined    : Improve.Model.Plan_Revision := Plan;
         Unrelated : Improve.Model.Task_Specification := Only;
         Evidence  : Improve.State.Verification_Vectors.Vector;
         Ordered   : Improve.Tasks.View_Vectors.Vector;
         Reordered : Improve.Tasks.View_Vectors.Vector;
         Summary   : Improve.Tasks.Finding_Summary;
      begin
         Unrelated.Id := To_Unbounded_String ("IMP-999999");
         Unrelated.Finding_Keys.Clear;
         Joined.Tasks.Append (Unrelated);
         Evidence.Append
           (Improve.State.Verification_Record'
              (Scope                => Improve.Model.Task_Evaluation,
               Task_Id              => Only.Id,
               Plan_Revision        => Joined.Revision,
               Contract_Fingerprint => To_Unbounded_String
                 (Improve.Model.Effective_Task_Contract_Fingerprint (Joined, Only.Id)),
               Assessment_Id        => 2,
               Outcome              => Improve.Model.Verified,
               Comparable           => True,
               Explanation          => To_Unbounded_String ("identity join")));
         Ordered := Improve.Tasks.Build
           (Joined, Improve.State.Publication_Vectors.Empty_Vector, Evidence, Current_Assessment => 2);
         Reordered.Append (Ordered.Last_Element);
         Reordered.Append (Ordered.First_Element);
         Summary := Improve.Tasks.Findings (Joined, Reordered);
         Assert (Summary.Resolved = 1, "finding aggregation used task/view position instead of task identity");
         Ordered := Improve.Tasks.Build
           (Joined, Improve.State.Publication_Vectors.Empty_Vector, Evidence, Current_Assessment => 0);
         Summary := Improve.Tasks.Findings (Joined, Ordered);
         Assert
           (Ordered.First_Element.Freshness = Improve.Tasks.Freshness_Unknown and then
            Summary.Unverified = 1 and then Summary.Previously_Resolved = 0,
            "unknown verification freshness was misclassified as historical resolution");
      end;
      declare
         Original  : Improve.Model.Plan_Revision := Plan;
         Revised   : Improve.Model.Plan_Revision;
         Dependent : Improve.Model.Task_Specification := Only;
         Evidence  : Improve.State.Verification_Vectors.Vector;
         Views     : Improve.Tasks.View_Vectors.Vector;
      begin
         Dependent.Id := To_Unbounded_String ("IMP-000002");
         Dependent.Finding_Keys.Clear;
         Dependent.Dependencies.Append (Only.Id);
         Original.Tasks.Append (Dependent);
         Revised := Original;
         Revised.Tasks (1).Goal := To_Unbounded_String ("Changed prerequisite contract");
         Evidence.Append
           (Improve.State.Verification_Record'
              (Scope                => Improve.Model.Task_Evaluation,
               Task_Id              => Dependent.Id,
               Plan_Revision        => Revised.Revision,
               Contract_Fingerprint => To_Unbounded_String
                 (Improve.Model.Effective_Task_Contract_Fingerprint (Original, Dependent.Id)),
               Assessment_Id        => 2,
               Outcome              => Improve.Model.Verified,
               Comparable           => True,
               Explanation          => To_Unbounded_String ("obsolete prerequisite binding")));
         Views := Improve.Tasks.Build
           (Revised, Improve.State.Publication_Vectors.Empty_Vector, Evidence, Current_Assessment => 2);
         Assert
           (not Views (2).Has_Verification,
            "dependent task reused verification from an obsolete prerequisite contract");
      end;
      declare
         Publications : Improve.State.Publication_Vectors.Vector;
         Evidence     : Improve.State.Verification_Vectors.Vector;
         Rejected     : Boolean := False;
         Mapping      : constant Improve.State.Publication_Record :=
           (Improve_Task_Id => Only.Id,
            Harness_Task_Id => To_Unbounded_String ("TASK-TEST-001"),
            Origin          => To_Unbounded_String ("improve:test"),
            Contract        => To_Unbounded_String
              (Improve.Model.Effective_Task_Contract_Fingerprint (Plan, Only.Id)),
            State           => To_Unbounded_String ("candidate"),
            Core_State      => Improve.Harness_States.Parse_Core ("candidate"),
            Plan_Revision   => Plan.Revision);
         Verification : constant Improve.State.Verification_Record :=
           (Scope                => Improve.Model.Task_Evaluation,
            Task_Id              => Only.Id,
            Plan_Revision        => Plan.Revision,
            Contract_Fingerprint => Mapping.Contract,
            Assessment_Id        => 2,
            Outcome              => Improve.Model.Verified,
            Comparable           => True,
            Explanation          => To_Unbounded_String ("duplicate"));
      begin
         Publications.Append (Mapping);
         Publications.Append (Mapping);
         begin
            declare Views : constant Improve.Tasks.View_Vectors.Vector :=
              Improve.Tasks.Build
                (Plan, Publications, Improve.State.Verification_Vectors.Empty_Vector);
               pragma Unreferenced (Views);
            begin
               null;
            end;
         exception
            when Improve.Data_Error => Rejected := True;
         end;
         Assert (Rejected, "duplicate publication mapping was silently selected");
         Evidence.Append (Verification);
         Evidence.Append (Verification);
         Rejected := False;
         begin
            declare Views : constant Improve.Tasks.View_Vectors.Vector :=
              Improve.Tasks.Build
                (Plan, Improve.State.Publication_Vectors.Empty_Vector, Evidence);
               pragma Unreferenced (Views);
            begin
               null;
            end;
         exception
            when Improve.Data_Error => Rejected := True;
         end;
         Assert (Rejected, "duplicate verification evidence was silently selected");
      end;
      Check ("", Improve.Tasks.Proposed);
      Check ("candidate", Improve.Tasks.Published);
      Check ("accepted", Improve.Tasks.Published);
      declare
         Unknown : constant Improve.Harness_States.State :=
           Improve.Harness_States.Parse_Core ("future-extension-state");
         Accepted : constant Improve.Harness_States.State :=
           Improve.Harness_States.Parse_Core ("accepted");
      begin
         Assert
           (not Improve.Harness_States.Is_Known (Unknown) and then
            Improve.Harness_States.Image (Unknown) = "" and then
            not Improve.Harness_States.Consistent ("parked", Accepted) and then
            not Improve.Harness_States.Consistent ("running", Accepted),
            "raw/core model_runner state binding was not enforced");
      end;
      Check ("running", Improve.Tasks.In_Progress);
      Check ("blocked", Improve.Tasks.Blocked);
      Check ("failed", Improve.Tasks.Failed);
      Check ("cancelled", Improve.Tasks.Cancelled);
      Check ("rejected", Improve.Tasks.Rejected);
      Check ("complete", Improve.Tasks.Awaiting_Verification);
      Check ("verification", Improve.Tasks.Awaiting_Verification);
      Check ("complete", Improve.Tasks.Verified, True, Improve.Model.Verified);
      Check ("running", Improve.Tasks.In_Progress, True, Improve.Model.Verified);
      Check ("complete", Improve.Tasks.Partially_Resolved, True, Improve.Model.Partially_Resolved);
      Check ("complete", Improve.Tasks.Still_Failing, True, Improve.Model.Still_Failing);
      Check ("complete", Improve.Tasks.Inconclusive, True, Improve.Model.Inconclusive);
      Check ("running", Improve.Tasks.Regressed, True, Improve.Model.Regressed);
      Check ("running", Improve.Tasks.Superseded, True, Improve.Model.Superseded);
      Check ("complete", Improve.Tasks.Awaiting_Verification, True, Improve.Model.Regressed, 3);
      Check ("complete", Improve.Tasks.Awaiting_Verification, True, Improve.Model.Superseded, 3);
      declare
         Views    : Improve.Tasks.View_Vectors.Vector :=
           Improve.Tasks.Build
             (Plan, Improve.State.Publication_Vectors.Empty_Vector,
              Improve.State.Verification_Vectors.Empty_Vector);
      begin
         Views (Views.First_Index).Harness_State := To_Unbounded_String ("unmapped-extension");
         Views (Views.First_Index).Harness_Core_State :=
           Improve.Harness_States.Parse_Core ("unmapped-extension");
         Views (Views.First_Index).Freshness := Improve.Tasks.Freshness_Current;
         Views (Views.First_Index).Quality := Improve.Model.Regressed;
         begin
            declare
               Returned : constant Improve.Tasks.Operational_Status :=
                 Improve.Tasks.Status (Views.First_Element);
            begin
               Assert
                 (False,
                  "an unrecognized cached harness state returned " & Improve.Tasks.Image (Returned));
            end;
         exception
            when Improve.Data_Error => null;
         end;
      end;
      Assert
        (Improve.Tasks.Valid_Filter ("unresolved") and then Improve.Tasks.Valid_Filter ("verified") and then
         not Improve.Tasks.Valid_Filter ("unknown") and then
         Improve.Tasks.Matches
           (Improve.Tasks.Build
              (Plan, Improve.State.Publication_Vectors.Empty_Vector,
               Improve.State.Verification_Vectors.Empty_Vector).First_Element,
            "unresolved"),
         "task status filter contract is inconsistent");
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Case_Access'(new Task_Case));
      return Result;
   end Suite;
end Improve_Tasks_Test_Suite;
