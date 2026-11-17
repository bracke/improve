with Ada.Strings.Fixed;
with Ada.Containers;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve.CLI;
with Improve.Model;
with Improve.State;
with Improve.Storage;
with Improve_Test_Support;

package body Improve_Verification_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Improve_Test_Support;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Model.Verification_Scope;
   use type Ada.Containers.Count_Type;

   type Test_Id is
     (Verification_Resolved, Verification_Still_Failing, Verification_Task_Scope_Not_Project,
      Verification_Severity_Drop_Outstanding, Verification_Partially_Resolved,
      Verification_Missing_Evidence, Verification_Regressed, Unrelated_Critical_Project_Regression,
      Out_Of_Order_Verification_Not_Regression, Changed_Contract_Not_Regression,
      Verification_Policy_Changed, Verification_Incomplete_Rejected, Verification_Revisions_Coexist);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_VERIFICATION_" & Test_Id'Image (Item.Id)));

   overriding procedure Run_Test (Item : in out Case_Test) is
begin
   case Item.Id is
         when Verification_Resolved =>
            declare
               Data   : constant Fixture := Build_Fixture ("verification_resolved");
               State  : constant String := To_String (Data.Directory) & "/improve.db";
               Plan   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Run    : Positive;
               Result : Improve.CLI.Outcome;
            begin
               Assert (Plan.Exit_Code = 0, "verification fixture plan failed");
               Run := Publish_Followup (Data);
               Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (Result.Output), """outcome"":""verified""") > 0,
                       "resolved verification failed: " & To_String (Result.Errors));
               Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Result.Exit_Code = 0, "repeated verification was not idempotent");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  declare Values : constant Improve.State.Verification_Vectors.Vector :=
                    Improve.Storage.Verifications (Improve_State, "PLAN-000001");
                  begin
                     Assert (Values.Length = 5, "repeated verification duplicated historical evidence");
                  end;
                  Improve.Storage.Close (Improve_State);
               end;
               Remove (Data);
            end;
         when Verification_Still_Failing =>
            declare
               Data   : constant Fixture := Build_Fixture ("verification_failing");
               State  : constant String := To_String (Data.Directory) & "/improve.db";
               Plan   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Run    : Positive;
               Result : Improve.CLI.Outcome;
            begin
               Assert (Plan.Exit_Code = 0, "verification fixture plan failed");
               Run := Publish_Followup (Data, Structure_State => Structure_Failing);
               Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Result.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                         (To_String (Result.Output), """outcome"":""still_failing""") > 0,
                       "unresolved verification did not return exit 1: " & To_String (Result.Errors));
               Remove (Data);
            end;
         when Verification_Task_Scope_Not_Project =>
            declare
               Data      : constant Fixture := Build_Fixture ("verification_scope");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Run       : Positive;
               Task_Run  : Improve.CLI.Outcome;
               Full_Run  : Improve.CLI.Outcome;
               Status    : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "verification-scope fixture plan failed");
               Run := Publish_Followup (Data, Structure_State => Structure_Failing);
               Task_Run := Improve.CLI.Execute
                 (Args ("verify|--task|IMP-000003|--run|" & Id_Image (Run) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Task_Run.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Task_Run.Output), """outcome"":""verified""") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Task_Run.Output), """project_outcome"":""unverified""") > 0,
                  "task-only verification claimed a project outcome");
               Task_Run := Improve.CLI.Execute
                 (Args ("verify|--task|IMP-000003|--run|" & Id_Image (Run) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Task_Run.Exit_Code = 0, "repeated task-scope verification was not idempotent");
               Status := Improve.CLI.Execute
                 (Args ("status|--project|" & Id_Image (Data.Project) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Status.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Status.Output), """plan_quality"":""unverified""") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Status.Output), """project_quality"":""unverified""") > 0,
                  "status inferred aggregate quality from one verified task");
               Full_Run := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Full_Run.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Full_Run.Output), """plan_outcome"":""still_failing""") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Full_Run.Output), """project_outcome"":""still_failing""") > 0,
                  "full verification did not preserve unresolved aggregate outcomes: " &
                    To_String (Full_Run.Errors));
               Full_Run := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Full_Run.Exit_Code = Improve.CLI.Negative_Exit,
                  "repeated full verification conflicted with task-scope evidence");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Assert
                    (Improve.Storage.Verifications (Improve_State, "PLAN-000001").Length = 5,
                     "verification scopes were duplicated or conflated");
                  Improve.Storage.Close (Improve_State);
               end;
               Remove (Data);
            end;
         when Verification_Severity_Drop_Outstanding =>
            declare
               Data     : constant Fixture := Build_Fixture ("verification_severity");
               State    : constant String := To_String (Data.Directory) & "/improve.db";
               Planned  : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Run      : Positive;
               Result   : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "severity fixture plan failed");
               Run := Publish_Followup
                 (Data, Structure_State => Structure_Failing,
                  Structure_Severity => Ada_Quality.Types.Info);
               Result := Improve.CLI.Execute
                 (Args ("verify|--task|IMP-000001|--run|" & Id_Image (Run) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Result.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Result.Output), """outcome"":""still_failing""") > 0,
                  "severity reduction incorrectly resolved the same finding fingerprint");
               Remove (Data);
            end;
         when Verification_Partially_Resolved =>
            declare
               Data   : constant Fixture := Build_Fixture ("verification_partial", Multiple_Structure => True);
               State  : constant String := To_String (Data.Directory) & "/improve.db";
               Plan   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Run    : Positive;
               Result : Improve.CLI.Outcome;
            begin
               Assert (Plan.Exit_Code = 0, "partial verification fixture plan failed");
               Run := Publish_Followup (Data, Structure_State => Structure_Failing);
               Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Result.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                         (To_String (Result.Output), """outcome"":""partially_resolved""") > 0,
                       "partial resolution was not preserved: " & To_String (Result.Errors));
               Remove (Data);
            end;
         when Verification_Missing_Evidence =>
            declare
               Data   : constant Fixture := Build_Fixture ("verification_missing");
               State  : constant String := To_String (Data.Directory) & "/improve.db";
               Plan   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Run    : Positive;
               Result : Improve.CLI.Outcome;
            begin
               Assert (Plan.Exit_Code = 0, "missing-evidence fixture plan failed");
               Run := Publish_Followup (Data, Structure_State => Structure_Unmeasurable);
               Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Result.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                         (To_String (Result.Output), """outcome"":""inconclusive""") > 0,
                       "unavailable evidence was not inconclusive: " & To_String (Result.Errors));
               Remove (Data);
            end;
         when Verification_Regressed =>
            declare
               Data       : constant Fixture := Build_Fixture ("verification_regressed");
               State      : constant String := To_String (Data.Directory) & "/improve.db";
               Plan       : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Resolved   : Positive;
               Returned   : Positive;
               First_Run  : Improve.CLI.Outcome;
               Second_Run : Improve.CLI.Outcome;
            begin
               Assert (Plan.Exit_Code = 0, "regression fixture plan failed");
               Resolved := Publish_Followup (Data, Source => "source-resolved");
               First_Run := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Resolved) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (First_Run.Exit_Code = 0, "initial resolution was not verified");
               Returned := Publish_Followup
                 (Data, Structure_State => Structure_Failing, Source => "source-regressed");
               Second_Run := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Returned) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Second_Run.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                         (To_String (Second_Run.Output), """outcome"":""regressed""") > 0,
                       "returned deficiency was not recorded as a regression: " & To_String (Second_Run.Errors));
               Remove (Data);
            end;
         when Unrelated_Critical_Project_Regression =>
            declare
               Data     : constant Fixture := Build_Fixture ("verification_project_regression");
               State    : constant String := To_String (Data.Directory) & "/improve.db";
               Planned  : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Run      : Positive;
               Result   : Improve.CLI.Outcome;
               Status   : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "project regression fixture plan failed");
               Run := Publish_Followup (Data, Source => "source-critical", New_Critical => True);
               Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Result.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Result.Output), """outcome"":""regressed""") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Result.Output), """new_critical"":1") > 0,
                  "unrelated critical finding did not regress project verification");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  for Evidence of Improve.Storage.Verifications (Improve_State, "PLAN-000001") loop
                     if Evidence.Scope = Improve.Model.Task_Evaluation then
                        Assert
                          (Evidence.Outcome = Improve.Model.Verified,
                           "task verification outcome was not preserved");
                     elsif Evidence.Scope = Improve.Model.Plan_Evaluation then
                        Assert
                          (Evidence.Outcome = Improve.Model.Verified,
                           "unrelated project regression changed the resolved plan outcome");
                     else
                        Assert
                          (Evidence.Outcome = Improve.Model.Regressed,
                           "project regression outcome was not persisted separately");
                     end if;
                  end loop;
                  Improve.Storage.Close (Improve_State);
               end;
               Status := Improve.CLI.Execute
                 (Args ("status|--project|" & Id_Image (Data.Project) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Status.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Status.Output), """project_quality"":""regressed""") > 0,
                  "project status lost the independently persisted regression");
               Remove (Data);
            end;
         when Out_Of_Order_Verification_Not_Regression =>
            declare
               Data       : constant Fixture := Build_Fixture ("verification_order");
               State      : constant String := To_String (Data.Directory) & "/improve.db";
               Planned    : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Older      : Positive;
               Newer      : Positive;
               New_Result : Improve.CLI.Outcome;
               Old_Result : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "verification ordering fixture plan failed");
               Older := Publish_Followup
                 (Data, Structure_State => Structure_Failing, Source => "source-older-failing");
               Newer := Publish_Followup (Data, Source => "source-newer-resolved");
               New_Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Newer) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (New_Result.Exit_Code = 0, "newer assessment was not verified first");
               Old_Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Older) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Old_Result.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Old_Result.Output), """outcome"":""still_failing""") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Old_Result.Output), """outcome"":""regressed""") = 0,
                  "future verification evidence incorrectly regressed an older assessment");
               Remove (Data);
            end;
         when Changed_Contract_Not_Regression =>
            declare
               Data      : constant Fixture := Build_Fixture ("changed_contract_history");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Resolved  : Positive;
               Returned  : Positive;
               Checked   : Improve.CLI.Outcome;
               Store     : Improve.Storage.Store;
               Next_Plan : Improve.Model.Plan_Revision;
               Saved     : Improve.Storage.Save_Result;
            begin
               Assert (Planned.Exit_Code = 0, "changed-contract fixture plan failed");
               Resolved := Publish_Followup (Data);
               Checked := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Resolved) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Checked.Exit_Code = 0, "original task contract was not verified");
               Improve.Storage.Open (Store, State, Writable => False);
               Next_Plan := Improve.Storage.Load (Store, "PLAN-000001");
               Improve.Storage.Close (Store);
               Next_Plan.Tasks (Next_Plan.Tasks.First_Index).Goal :=
                 To_Unbounded_String ("A materially revised remediation goal");
               Next_Plan.Fingerprint := To_Unbounded_String
                 (Improve.Stable_Digest ("changed-task-contract-revision"));
               Improve.Storage.Open (Store, State, Writable => True);
               Saved := Improve.Storage.Save (Store, Next_Plan);
               Improve.Storage.Close (Store);
               Assert
                 (not Saved.Existing and then Saved.Plan.Revision = 2 and then
                  Saved.Plan.Tasks.First_Element.Id = To_Unbounded_String ("IMP-000001"),
                  "changed contract did not retain the logical task identity fixture");
               Returned := Publish_Followup (Data, Structure_State => Structure_Failing);
               Checked := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--revision|2|--run|" &
                        Id_Image (Returned) & "|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Checked.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Checked.Output), """outcome"":""still_failing""") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Checked.Output), """outcome"":""regressed""") = 0,
                  "verification reused resolution history from a different task contract");
               Remove (Data);
            end;
         when Verification_Policy_Changed =>
            declare
               Data   : constant Fixture := Build_Fixture ("verification_policy");
               State  : constant String := To_String (Data.Directory) & "/improve.db";
               Plan   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Run    : Positive;
               Result : Improve.CLI.Outcome;
            begin
               Assert (Plan.Exit_Code = 0, "verification fixture plan failed");
               Run := Publish_Followup (Data, Policy => "policy-b");
               Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Result.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                         (To_String (Result.Output), """outcome"":""inconclusive""") > 0,
                       "policy change was not inconclusive: " & To_String (Result.Errors));
               Remove (Data);
            end;
         when Verification_Incomplete_Rejected =>
            declare
               Data   : constant Fixture := Build_Fixture ("verification_incomplete");
               State  : constant String := To_String (Data.Directory) & "/improve.db";
               Plan   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Result : Improve.CLI.Outcome;
            begin
               Assert (Plan.Exit_Code = 0, "incomplete verification fixture plan failed");
               Result := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Data.Interrupted) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Result.Exit_Code = Improve.CLI.Unavailable_Exit and then Length (Result.Output) = 0,
                       "incomplete measurement was not rejected");
               Remove (Data);
            end;
         when Verification_Revisions_Coexist =>
            declare
               Data       : constant Fixture := Build_Fixture ("verification_revisions");
               State      : constant String := To_String (Data.Directory) & "/improve.db";
               First      : Improve.Model.Plan_Revision := Draft_For (Data);
               Second     : Improve.Model.Plan_Revision;
               Store      : Improve.Storage.Store;
               Saved      : Improve.Storage.Save_Result;
               Removed_Id : Unbounded_String;
               Run        : Positive;
               Revision_1 : Improve.CLI.Outcome;
               Revision_2 : Improve.CLI.Outcome;
               Plan_Count : Natural := 0;
               Structure_Key : Unbounded_String;
            begin
               for Finding of First.Findings loop
                  if To_String (Finding.Fingerprint) =
                    Finding_Fingerprint
                      (Ada_Quality.Types.STR_01, "manifest.invalid", "alire.toml", "manifest is invalid")
                  then
                     Structure_Key := To_Unbounded_String (Improve.Model.Finding_Key (Finding));
                     exit;
                  end if;
               end loop;
               for Index in 1 .. Natural (First.Tasks.Length) loop
                  if First.Tasks (Index).Finding_Keys.Contains (Structure_Key) then
                     Removed_Id := First.Tasks (Index).Id;
                     First.Tasks.Delete (Index);
                     exit;
                  end if;
               end loop;
               Assert (Length (Removed_Id) > 0, "revision fixture did not identify the structure task");
               for Task_Index in 1 .. Natural (First.Tasks.Length) loop
                  for Index in reverse 1 .. Natural (First.Tasks (Task_Index).Dependencies.Length) loop
                     if First.Tasks (Task_Index).Dependencies (Index) = Removed_Id then
                        First.Tasks (Task_Index).Dependencies.Delete (Index);
                     end if;
                  end loop;
               end loop;
               First.Fingerprint := To_Unbounded_String
                 (Improve.Stable_Digest ("revision-one-without-structure-task"));
               Improve.Storage.Open (Store, State, Writable => True);
               Saved := Improve.Storage.Save (Store, First);
               Assert (not Saved.Existing and then Saved.Plan.Revision = 1, "first revision was not persisted");
               Second := Draft_For (Data);
               Saved := Improve.Storage.Save (Store, Second);
               Assert (not Saved.Existing and then Saved.Plan.Revision = 2, "second revision was not persisted");
               Improve.Storage.Close (Store);
               Run := Publish_Followup (Data, Structure_State => Structure_Failing);
               Revision_1 := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--revision|1|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Revision_2 := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--revision|2|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Revision_1.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Revision_1.Output), """outcome"":""verified""") > 0,
                  "first historical revision did not retain its valid outcome");
               Assert
                 (Revision_2.Exit_Code = Improve.CLI.Negative_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Revision_2.Output), """outcome"":""still_failing""") > 0,
                  "second historical revision did not retain its distinct outcome");
               Revision_1 := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--revision|1|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Revision_2 := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--revision|2|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Revision_1.Exit_Code = 0 and then Revision_2.Exit_Code = Improve.CLI.Negative_Exit,
                  "exact-revision verification was not idempotent");
               Improve.Storage.Open (Store, State, Writable => False);
               for Evidence of Improve.Storage.Verifications (Store, "PLAN-000001") loop
                  if Evidence.Scope = Improve.Model.Plan_Evaluation then
                     Assert
                       (Evidence.Plan_Revision in 1 | 2 and then Length (Evidence.Contract_Fingerprint) > 0,
                        "plan verification lost immutable revision provenance");
                     Plan_Count := Plan_Count + 1;
                  end if;
               end loop;
               Improve.Storage.Close (Store);
               Assert (Plan_Count = 2, "verification revisions conflicted or duplicated");
               Remove (Data);
            end;
   end case;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      for Id in Test_Id loop
         Result.Add_Test (Case_Access'(new Case_Test (Id)));
      end loop;
      return Result;
   end Suite;
end Improve_Verification_Test_Suite;
