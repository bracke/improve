with Ada.Exceptions;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve;
with Improve.CLI;
with Improve.Model;
with Improve.Storage;
with Improve.Workflow;
with Improve_Test_Support;
with Model_Runner.Errors;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Schemas;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;

package body Improve_Publication_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Improve_Test_Support;
   use type Ada.Containers.Count_Type;

   type Test_Id is
     (Native_Publication_And_Recovery, Native_Task_Contract_Fidelity, Changed_Task_Contract_Replaced,
      Replacement_Running_And_Completed, Workspace_Lifecycle_Fails_Closed,
      Selective_Publication_Resolves_Dependency, Prerequisite_Replacement_Migrates_Dependents,
      Refresh_Reconciles_State);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_PUBLICATION_" & Test_Id'Image (Item.Id)));

   overriding procedure Run_Test (Item : in out Case_Test) is
begin
   case Item.Id is
         when Native_Publication_And_Recovery =>
            declare
               package Errors renames Model_Runner.Errors;
               package Records renames Model_Runner.Framework.Records;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data    : constant Fixture := Build_Fixture ("native_publication");
               State   : constant String := To_String (Data.Directory) & "/improve.db";
               Plan_Result : Improve.CLI.Outcome;
               Preview_Result : Improve.CLI.Outcome;
               Apply_Result : Improve.CLI.Outcome;
               Retry_Result : Improve.CLI.Outcome;
               Store   : Stores.Store;
               Status  : Errors.Error_Info;
            begin
               declare
                  Draft    : constant Improve.Model.Plan_Revision := Draft_For (Data);
                  Rejected : Boolean := False;
               begin
                  begin
                     declare
                        Value : constant Improve.Workflow.Publication_Result :=
                          Improve.Workflow.Publish (To_String (Data.Target), Draft, "auto");
                        pragma Unreferenced (Value);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Dependency_Error => Rejected := True;
                  end;
                  Assert (Rejected, "publication accepted uninitialized harness state");

                  Rejected := False;
                  begin
                     declare
                        Value : constant Improve.Workflow.Published_Vectors.Vector :=
                          Improve.Workflow.Reconcile
                            (To_String (Data.Target), Improve.Workflow.Published_Vectors.Empty_Vector);
                        pragma Unreferenced (Value);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Dependency_Error => Rejected := True;
                  end;
                  Assert (Rejected, "reconciliation accepted uninitialized harness state");
               end;
               Plan_Result := Improve.CLI.Execute
                 (Args ("plan|--database|" & To_String (Data.Database) & "|--state|" & State & "|--project|" &
                        Id_Image (Data.Project) & "|--format|json"));
               Assert (Plan_Result.Exit_Code = 0, "publication fixture plan failed: " & To_String (Plan_Result.Errors));
               Initialize_Harness (To_String (Data.Target));
               Preview_Result := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--dry-run|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Preview_Result.Exit_Code = 0,
                  "publication preview failed: " & To_String (Preview_Result.Errors));
               Stores.Open_To_Read (Store, To_String (Data.Target), Status);
               Assert (Errors.Is_Ok (Status) and then Tasks.List (Store).Is_Empty,
                       "publication preview modified harness state");
               Stores.Close (Store);
               Approve_Latest (State);
               Apply_Result := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert (Apply_Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (Apply_Result.Output), """task_kind"":""remediation""") > 0,
                       "native publication failed: " & To_String (Apply_Result.Errors));
               Stores.Open_To_Read (Store, To_String (Data.Target), Status);
               Assert (Errors.Is_Ok (Status), "published harness state could not be opened");
               declare Ids : constant Model_Runner.Framework.Name_Lists.Vector := Tasks.List (Store); begin
                  Assert (Ids.Length = 3, "native publication did not create exactly three tasks");
                  for Id of Ids loop
                     declare Definition : Records.Item; begin
                        Tasks.Definition (Store, Id, Definition, Status);
                        Assert
                          (Errors.Is_Ok (Status) and then
                           Records.Get (Definition, "created_by") = "improve" and then
                                Ada.Strings.Fixed.Index (Records.Get (Definition, "origin"), "improve:") = 1 and then
                                Tasks.State_Of (Store, Id) = "candidate",
                                "published task lost provenance or candidate state");
                     end;
                  end loop;
               end;
               Stores.Close (Store);
               Retry_Result := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert (Retry_Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (Retry_Result.Output), """recovered"":true") > 0,
                       "repeated apply did not recover by stable origin: " & To_String (Retry_Result.Errors));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  declare Mappings : constant Improve.Storage.Publication_Vectors.Vector :=
                    Improve.Storage.Publications (Improve_State, "PLAN-000001");
                  begin
                     Assert (Mappings.Length = 3, "publication mappings were not persisted exactly once");
                  end;
                  Improve.Storage.Close (Improve_State);
               end;
               Remove (Data);
            end;
         when Native_Task_Contract_Fidelity =>
            declare
               package Errors renames Model_Runner.Errors;
               package Records renames Model_Runner.Framework.Records;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data       : constant Fixture := Build_Fixture ("native_contract");
               Plan       : Improve.Model.Plan_Revision := Draft_For (Data);
               Spec       : Improve.Model.Task_Specification := Plan.Tasks (1);
               Published  : Improve.Workflow.Publication_Result;
               Harness    : Stores.Store;
               Status     : Errors.Error_Info;
               Definition : Records.Item;
            begin
               Spec.Goal := To_Unbounded_String ("contract goal marker");
               Spec.Problem := To_Unbounded_String ("contract problem marker");
               Spec.Evidence := To_Unbounded_String ("contract evidence marker");
               Spec.Relevant_Files.Clear;
               Spec.Relevant_Files.Append (To_Unbounded_String ("src/contract_entry.adb"));
               Spec.Relevant_Files.Append (To_Unbounded_String ("tests/contract_entry_tests.adb"));
               Spec.Scope := To_Unbounded_String ("contract scope marker");
               Spec.Out_Of_Scope := To_Unbounded_String ("contract exclusion marker");
               Spec.Requirements := To_Unbounded_String ("contract requirement marker");
               Spec.Acceptance := To_Unbounded_String ("contract acceptance marker");
               Spec.Verification := To_Unbounded_String ("contract verification marker");
               Plan.Tasks.Replace_Element (1, Spec);
               Initialize_Harness (To_String (Data.Target));
               Published := Improve.Workflow.Publish (To_String (Data.Target), Plan, "auto");
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Tasks.Definition
                 (Harness, To_String (Published.Tasks (1).Harness_Id), Definition, Status);
               declare Notes : constant String := Records.Get (Definition, "notes"); begin
                  Assert
                    (Errors.Is_Ok (Status) and then
                     Records.Get (Definition, "title") = To_String (Spec.Title) and then
                     Records.Get (Definition, "priority") = "75" and then
                     Records.Get (Definition, "acceptance") = "contract acceptance marker" and then
                     Ada.Strings.Fixed.Index (Notes, Improve.Model.Task_Contract_Fingerprint (Spec)) > 0 and then
                     Ada.Strings.Fixed.Index (Notes, "contract goal marker") > 0 and then
                     Ada.Strings.Fixed.Index (Notes, "contract problem marker") > 0 and then
                     Ada.Strings.Fixed.Index (Notes, "contract evidence marker") > 0 and then
                     Ada.Strings.Fixed.Index (Notes, "src/contract_entry.adb") > 0 and then
                     Ada.Strings.Fixed.Index (Notes, "tests/contract_entry_tests.adb") > 0 and then
                     Ada.Strings.Fixed.Index (Notes, "contract scope marker") > 0 and then
                     Ada.Strings.Fixed.Index (Notes, "contract exclusion marker") > 0 and then
                     Ada.Strings.Fixed.Index (Notes, "contract requirement marker") > 0 and then
                     Ada.Strings.Fixed.Index (Notes, "contract verification marker") > 0,
                     "native task omitted execution-relevant Improve contract fields");
               end;
               Stores.Close (Harness);
               Remove (Data);
            end;
         when Changed_Task_Contract_Replaced =>
            declare
               package Errors renames Model_Runner.Errors;
               package Records renames Model_Runner.Framework.Records;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data       : constant Fixture := Build_Fixture ("changed_contract");
               State      : constant String := To_String (Data.Directory) & "/improve.db";
               First      : Improve.Storage.Save_Result;
               Second     : Improve.Storage.Save_Result;
               Draft      : Improve.Model.Plan_Revision := Draft_For (Data);
               Published  : Improve.Workflow.Publication_Result;
               Republished : Improve.Workflow.Publication_Result;
               Mappings   : Improve.Storage.Publication_Vectors.Vector;
               Harness    : Stores.Store;
               Recovery   : Stores.Recovery_Report;
               Status     : Errors.Error_Info;
               Definition : Records.Item;

               procedure Move_Task (Id, Next : String; Gates_Passed : Boolean := False) is
                  Change : Stores.Transaction;
               begin
                  Tasks.Move
                    (Harness, Change, Id, Next, "", Gates_Passed => Gates_Passed,
                     Status => Status, Actor => "improve-test");
                  Assert (Errors.Is_Ok (Status), "could not move native task to " & Next);
                  Stores.Commit (Harness, Change, Status);
                  Assert (Errors.Is_Ok (Status), "could not commit native task state " & Next);
               end Move_Task;
            begin
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  First := Improve.Storage.Save (Improve_State, Draft);
                  Improve.Storage.Close (Improve_State);
               end;
               Initialize_Harness (To_String (Data.Target));
               Published := Improve.Workflow.Publish (To_String (Data.Target), First.Plan, "auto");
               for Value of Published.Tasks loop
                  Mappings.Append
                    (Improve.Storage.Publication_Record'
                       (Value.Improve_Id, Value.Harness_Id, Value.Origin, Value.Contract,
                        Value.State, First.Plan.Revision));
               end loop;
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Improve.Storage.Record_Publications
                    (Improve_State, To_String (First.Plan.Plan_Id), Mappings);
                  Improve.Storage.Close (Improve_State);
               end;
               Stores.Open (Harness, To_String (Data.Target), Recovery, Status);
               Assert (Errors.Is_Ok (Status), "could not open harness to accept original native task");
               Move_Task (To_String (Published.Tasks (1).Harness_Id), "accepted");
               Move_Task (To_String (Published.Tasks (3).Harness_Id), "accepted");
               Move_Task (To_String (Published.Tasks (3).Harness_Id), "running");
               Move_Task (To_String (Published.Tasks (3).Harness_Id), "failed");
               Stores.Close (Harness);

               Draft.Tasks (1).Scope := To_Unbounded_String ("expanded scope contract marker");
               Draft.Tasks (2).Scope := To_Unbounded_String ("replacement for candidate predecessor");
               Draft.Tasks (3).Scope := To_Unbounded_String ("replacement for failed predecessor");
               Draft.Fingerprint := To_Unbounded_String
                 (Improve.Stable_Digest (To_String (Draft.Fingerprint) & ":expanded-scope"));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Second := Improve.Storage.Save (Improve_State, Draft);
                  Mappings := Improve.Storage.Publications (Improve_State, To_String (First.Plan.Plan_Id));
                  Improve.Storage.Close (Improve_State);
               end;
               Assert
                 (Second.Plan.Tasks (1).Id = First.Plan.Tasks (1).Id and then
                  Second.Plan.Tasks (2).Id = First.Plan.Tasks (2).Id,
                  "logical task continuity was not preserved across a changed contract");
               Republished := Improve.Workflow.Publish
                 (To_String (Data.Target), Second.Plan, "auto", Existing => Mappings);
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Tasks.Definition
                 (Harness, To_String (Republished.Tasks (1).Harness_Id), Definition, Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 6 and then
                  Republished.Tasks (1).Harness_Id /= Published.Tasks (1).Harness_Id and then
                  Tasks.State_Of (Harness, To_String (Published.Tasks (1).Harness_Id)) = "cancelled" and then
                  Tasks.State_Of (Harness, To_String (Published.Tasks (2).Harness_Id)) = "rejected" and then
                  Tasks.State_Of (Harness, To_String (Published.Tasks (3).Harness_Id)) = "cancelled" and then
                  Tasks.State_Of (Harness, To_String (Republished.Tasks (1).Harness_Id)) = "candidate" and then
                  Ada.Strings.Fixed.Index
                    (Records.Get (Definition, "notes"), "expanded scope contract marker") > 0 and then
                  Ada.Strings.Fixed.Index
                    (Records.Get (Definition, "notes"),
                     "Supersedes: " & To_String (Published.Tasks (1).Harness_Id)) > 0,
                  "changed task contract did not retire and trace its accepted predecessor");
               declare Work : constant Tasks.Next_Work := Tasks.Next_Work_Of (Harness); begin
                  Assert
                    (Work.Awaiting.Contains (To_String (Republished.Tasks (1).Harness_Id)) and then
                     Work.Awaiting.Contains (To_String (Republished.Tasks (2).Harness_Id)) and then
                     Work.Awaiting.Contains (To_String (Republished.Tasks (3).Harness_Id)) and then
                     not Work.Runnable.Contains (To_String (Published.Tasks (1).Harness_Id)) and then
                     not Work.Running.Contains (To_String (Published.Tasks (1).Harness_Id)),
                     "normal work selection retained both predecessor and replacement");
               end;
               Stores.Close (Harness);
               declare Replacement_Mappings : Improve.Storage.Publication_Vectors.Vector; begin
                  for Value of Republished.Tasks loop
                     Replacement_Mappings.Append
                       (Improve.Storage.Publication_Record'
                          (Value.Improve_Id, Value.Harness_Id, Value.Origin, Value.Contract,
                           Value.State, Second.Plan.Revision));
                  end loop;
                  declare Improve_State : Improve.Storage.Store; begin
                     Improve.Storage.Open (Improve_State, State, Writable => True);
                     Improve.Storage.Record_Publications
                       (Improve_State, To_String (Second.Plan.Plan_Id), Replacement_Mappings);
                     Improve.Storage.Close (Improve_State);
                  end;
               end;
               Stores.Open (Harness, To_String (Data.Target), Recovery, Status);
               Assert (Errors.Is_Ok (Status), "could not open harness to establish distinct task states");
               Move_Task (To_String (Republished.Tasks (1).Harness_Id), "accepted");
               Move_Task (To_String (Republished.Tasks (1).Harness_Id), "running");
               Stores.Close (Harness);
               declare
                  Refreshed : constant Improve.CLI.Outcome := Improve.CLI.Execute
                    (Args ("refresh|--project|" & Id_Image (Data.Project) & "|--database|" &
                           To_String (Data.Database) & "|--state|" & State & "|--format|json"));
                  Listed : constant Improve.CLI.Outcome := Improve.CLI.Execute
                    (Args ("tasks|--project|" & Id_Image (Data.Project) & "|--database|" &
                           To_String (Data.Database) & "|--state|" & State & "|--format|json"));
                  Summary : constant Improve.CLI.Outcome := Improve.CLI.Execute
                    (Args ("status|--project|" & Id_Image (Data.Project) & "|--database|" &
                           To_String (Data.Database) & "|--state|" & State & "|--format|json"));
                  New_Id : constant String := To_String (Republished.Tasks (1).Harness_Id);
                  Old_Id : constant String := To_String (Published.Tasks (1).Harness_Id);
               begin
                  Assert (Refreshed.Exit_Code = 0, "replacement task state reconciliation failed");
                  Assert
                    (Listed.Exit_Code = 0 and then
                     Ada.Strings.Fixed.Index (To_String (Listed.Output), New_Id) > 0 and then
                     Ada.Strings.Fixed.Index (To_String (Listed.Output), Old_Id) = 0 and then
                     Ada.Strings.Fixed.Index (To_String (Listed.Output), """status"":""in_progress""") > 0,
                     "task JSON selected the obsolete native contract mapping");
                  Assert
                    (Summary.Exit_Code = 0 and then
                     Ada.Strings.Fixed.Index (To_String (Summary.Output), New_Id) > 0 and then
                     Ada.Strings.Fixed.Index (To_String (Summary.Output), Old_Id) = 0 and then
                     Ada.Strings.Fixed.Index (To_String (Summary.Output), """harness_state"":""running""") > 0,
                     "status JSON selected the obsolete native contract mapping");
               end;
               Remove (Data);
            end;
         when Replacement_Running_And_Completed =>
            declare
               package Errors renames Model_Runner.Errors;
               package Records renames Model_Runner.Framework.Records;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data        : constant Fixture := Build_Fixture ("replacement_states");
               State       : constant String := To_String (Data.Directory) & "/improve.db";
               Draft       : Improve.Model.Plan_Revision := Draft_For (Data);
               First       : Improve.Storage.Save_Result;
               Second      : Improve.Storage.Save_Result;
               Published   : Improve.Workflow.Publication_Result;
               Republished : Improve.Workflow.Publication_Result;
               Mappings    : Improve.Storage.Publication_Vectors.Vector;
               Harness     : Stores.Store;
               Recovery    : Stores.Recovery_Report;
               Status      : Errors.Error_Info;

               procedure Move_Task (Id, Next : String; Gates_Passed : Boolean := False) is
                  Change : Stores.Transaction;
               begin
                  Tasks.Move
                    (Harness, Change, Id, Next, "", Gates_Passed => Gates_Passed,
                     Status => Status, Actor => "improve-test");
                  Assert (Errors.Is_Ok (Status), "could not move replacement-state task to " & Next);
                  Stores.Commit (Harness, Change, Status);
                  Assert (Errors.Is_Ok (Status), "could not commit replacement-state task " & Next);
               end Move_Task;
            begin
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  First := Improve.Storage.Save (Improve_State, Draft);
                  Improve.Storage.Close (Improve_State);
               end;
               Initialize_Harness (To_String (Data.Target));
               Published := Improve.Workflow.Publish (To_String (Data.Target), First.Plan, "auto");
               for Value of Published.Tasks loop
                  Mappings.Append
                    (Improve.Storage.Publication_Record'
                       (Value.Improve_Id, Value.Harness_Id, Value.Origin, Value.Contract,
                        Value.State, First.Plan.Revision));
               end loop;
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Improve.Storage.Record_Publications
                    (Improve_State, To_String (First.Plan.Plan_Id), Mappings);
                  Improve.Storage.Close (Improve_State);
               end;
               Stores.Open (Harness, To_String (Data.Target), Recovery, Status);
               Assert (Errors.Is_Ok (Status), "could not open replacement-state harness");
               Move_Task (To_String (Published.Tasks (1).Harness_Id), "accepted");
               Move_Task (To_String (Published.Tasks (1).Harness_Id), "running");
               Move_Task (To_String (Published.Tasks (1).Harness_Id), "verification");
               Move_Task (To_String (Published.Tasks (1).Harness_Id), "complete", Gates_Passed => True);
               Move_Task (To_String (Published.Tasks (2).Harness_Id), "accepted");
               Move_Task (To_String (Published.Tasks (2).Harness_Id), "running");
               Stores.Close (Harness);

               Draft.Tasks (1).Scope := To_Unbounded_String ("replacement after completed predecessor");
               Draft.Tasks (2).Scope := To_Unbounded_String ("replacement after running predecessor");
               Draft.Fingerprint := To_Unbounded_String
                 (Improve.Stable_Digest (To_String (Draft.Fingerprint) & ":running-complete"));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Second := Improve.Storage.Save (Improve_State, Draft);
                  Mappings := Improve.Storage.Publications (Improve_State, To_String (First.Plan.Plan_Id));
                  Improve.Storage.Close (Improve_State);
               end;
               declare Blocked : Boolean := False; begin
                  begin
                     Republished := Improve.Workflow.Publish
                       (To_String (Data.Target), Second.Plan, "auto", Existing => Mappings);
                  exception
                     when Error : Improve.Data_Error =>
                        Blocked := Ada.Strings.Fixed.Index
                          (Ada.Exceptions.Exception_Message (Error), "while native predecessor") > 0;
                  end;
                  Assert (Blocked, "running native predecessor did not block automatic replacement");
               end;
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 3 and then
                  Tasks.State_Of (Harness, To_String (Published.Tasks (1).Harness_Id)) = "complete" and then
                  Tasks.State_Of (Harness, To_String (Published.Tasks (2).Harness_Id)) = "running",
                  "blocked replacement partially changed native task state");
               Stores.Close (Harness);

               Stores.Open (Harness, To_String (Data.Target), Recovery, Status);
               Move_Task (To_String (Published.Tasks (2).Harness_Id), "cancelled");
               Stores.Close (Harness);
               Republished := Improve.Workflow.Publish
                 (To_String (Data.Target), Second.Plan, "auto", Existing => Mappings);
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               declare Definition : Records.Item; begin
                  Tasks.Definition
                    (Harness, To_String (Republished.Tasks (1).Harness_Id), Definition, Status);
                  Assert
                    (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 5 and then
                     Tasks.State_Of (Harness, To_String (Published.Tasks (1).Harness_Id)) = "complete" and then
                     Tasks.State_Of (Harness, To_String (Published.Tasks (2).Harness_Id)) = "cancelled" and then
                     Tasks.State_Of (Harness, To_String (Republished.Tasks (1).Harness_Id)) = "candidate" and then
                     Ada.Strings.Fixed.Index
                       (Records.Get (Definition, "notes"),
                        "Supersedes: " & To_String (Published.Tasks (1).Harness_Id)) > 0,
                     "completed predecessor was not preserved as traced historical work");
               end;
               Stores.Close (Harness);
               Remove (Data);
            end;
         when Workspace_Lifecycle_Fails_Closed =>
            declare
               package Errors renames Model_Runner.Errors;
               package Records renames Model_Runner.Framework.Records;
               package Schemas renames Model_Runner.Framework.Schemas;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("workspace_fail_closed");
               Plan      : constant Improve.Model.Plan_Revision := Draft_For (Data);
               Published : Improve.Workflow.Publication_Result;
               Store     : Stores.Store;
               Recovery  : Stores.Recovery_Report;
               Status    : Errors.Error_Info;
               Change    : Stores.Transaction;
               Workspace : Records.Item;
               Task_Id   : Unbounded_String;

               procedure Move_Task (Next : String) is
                  Move_Change : Stores.Transaction;
               begin
                  Tasks.Move
                    (Store, Move_Change, To_String (Task_Id), Next, "test transition", Status => Status,
                     Actor => "improve-test");
                  Assert (Errors.Is_Ok (Status), "could not establish " & Next & " workspace fixture state");
                  Stores.Commit (Store, Move_Change, Status);
                  Assert (Errors.Is_Ok (Status), "could not commit " & Next & " workspace fixture state");
               end Move_Task;
            begin
               Initialize_Harness (To_String (Data.Target));
               Published := Improve.Workflow.Publish (To_String (Data.Target), Plan, "auto");
               Task_Id := Published.Tasks.First_Element.Harness_Id;
               Stores.Open (Store, To_String (Data.Target), Recovery, Status);
               Assert (Errors.Is_Ok (Status), "could not open workspace fail-closed fixture");
               Move_Task ("accepted");
               Move_Task ("running");
               Move_Task ("blocked");
               Workspace := Records.Create (Schemas.Workspace_Schema, 1, "WORKSPACE-TEST", 1);
               Records.Set (Workspace, "backend", "file_copy");
               Records.Set (Workspace, "path", "/tmp/improve-unmanaged-workspace");
               Records.Set (Workspace, "base", "baseline");
               Records.Set (Workspace, "agent", "test-agent");
               Records.Set (Workspace, "task", To_String (Task_Id));
               Records.Set (Workspace, "status", "active");
               Stores.Put (Change, Model_Runner.Framework.Workspaces_Area, "WORKSPACE-TEST", Workspace);
               Stores.Commit (Store, Change, Status);
               Assert (Errors.Is_Ok (Status), "could not commit active workspace fixture");
               Tasks.Move
                 (Store, Change, To_String (Task_Id), "cancelled", "replacement", Status => Status,
                  Actor => "improve-test");
               Assert
                 (Errors.Is_Error (Status) and then Tasks.State_Of (Store, To_String (Task_Id)) = "blocked",
                  "lightweight lifecycle abandoned or ignored an unmanaged active workspace");
               Stores.Close (Store);
               Remove (Data);
            end;
         when Selective_Publication_Resolves_Dependency =>
            declare
               package Errors renames Model_Runner.Errors;
               package Records renames Model_Runner.Framework.Records;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("selective_dependency");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Draft     : Improve.Model.Plan_Revision := Draft_For (Data);
               Stored    : Improve.Storage.Save_Result;
               Result    : Improve.CLI.Outcome;
               First_Map : Improve.Storage.Publication_Record;
               Next_Map  : Improve.Storage.Publication_Record;
               Harness   : Stores.Store;
               Status    : Errors.Error_Info;
               Definition : Records.Item;
            begin
               Draft.Tasks (2).Dependencies.Append (Draft.Tasks (1).Id);
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Stored := Improve.Storage.Save (Improve_State, Draft);
                  Improve.Storage.Approve
                    (Improve_State, To_String (Stored.Plan.Plan_Id), Stored.Plan.Revision);
                  Improve.Storage.Close (Improve_State);
               end;
               Initialize_Harness (To_String (Data.Target));
               Result := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--task|IMP-000002|--database|" & To_String (Data.Database) &
                        "|--state|" & State & "|--format|json"));
               Assert
                 (Result.Exit_Code = Improve.CLI.Failure_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Result.Errors), "requires unpublished prerequisite IMP-000001") > 0,
                  "selective publication did not identify its unpublished prerequisite");
               Result := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--task|IMP-000001|--database|" & To_String (Data.Database) &
                        "|--state|" & State & "|--format|json"));
               Assert (Result.Exit_Code = 0, "prerequisite task publication failed");
               Result := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--task|IMP-000002|--database|" & To_String (Data.Database) &
                        "|--state|" & State & "|--format|json"));
               Assert
                 (Result.Exit_Code = 0,
                  "dependent task did not reuse its published prerequisite: " & To_String (Result.Errors));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  for Mapping of Improve.Storage.Publications (Improve_State, "PLAN-000001") loop
                     if To_String (Mapping.Improve_Task_Id) = "IMP-000001" then First_Map := Mapping;
                     elsif To_String (Mapping.Improve_Task_Id) = "IMP-000002" then Next_Map := Mapping;
                     end if;
                  end loop;
                  Improve.Storage.Close (Improve_State);
               end;
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Tasks.Definition (Harness, To_String (Next_Map.Harness_Task_Id), Definition, Status);
               Assert
                 (Errors.Is_Ok (Status) and then
                  Records.Get (Definition, "depends_on") = To_String (First_Map.Harness_Task_Id),
                  "native dependent task lost its already-published prerequisite identity");
               Stores.Close (Harness);
               Remove (Data);
            end;
         when Prerequisite_Replacement_Migrates_Dependents =>
            declare
               package Errors renames Model_Runner.Errors;
               package Records renames Model_Runner.Framework.Records;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data        : constant Fixture := Build_Fixture ("dependency_replacement");
               State       : constant String := To_String (Data.Directory) & "/improve.db";
               Draft       : Improve.Model.Plan_Revision := Draft_For (Data);
               First       : Improve.Storage.Save_Result;
               Second      : Improve.Storage.Save_Result;
               Third       : Improve.Storage.Save_Result;
               Published   : Improve.Workflow.Publication_Result;
               Republished : Improve.Workflow.Publication_Result;
               Mappings    : Improve.Storage.Publication_Vectors.Vector;
               Selected    : Improve.Model.UString_Vectors.Vector;
               Harness     : Stores.Store;
               Recovery    : Stores.Recovery_Report;
               Status      : Errors.Error_Info;

               procedure Move_Task (Id, Next : String; Gates_Passed : Boolean := False) is
                  Change : Stores.Transaction;
               begin
                  Tasks.Move
                    (Harness, Change, Id, Next, "", Gates_Passed => Gates_Passed,
                     Status => Status, Actor => "improve-test");
                  Assert (Errors.Is_Ok (Status), "could not move dependency replacement task to " & Next);
                  Stores.Commit (Harness, Change, Status);
                  Assert (Errors.Is_Ok (Status), "could not commit dependency replacement state " & Next);
               end Move_Task;
            begin
               Draft.Tasks (2).Dependencies.Append (Draft.Tasks (1).Id);
               Draft.Fingerprint := To_Unbounded_String
                 (Improve.Stable_Digest (To_String (Draft.Fingerprint) & ":dependency-edge"));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  First := Improve.Storage.Save (Improve_State, Draft);
                  Improve.Storage.Close (Improve_State);
               end;
               Initialize_Harness (To_String (Data.Target));
               Published := Improve.Workflow.Publish (To_String (Data.Target), First.Plan, "auto");
               for Value of Published.Tasks loop
                  Mappings.Append
                    (Improve.Storage.Publication_Record'
                       (Value.Improve_Id, Value.Harness_Id, Value.Origin, Value.Contract,
                        Value.State, First.Plan.Revision));
               end loop;
               Stores.Open (Harness, To_String (Data.Target), Recovery, Status);
               Assert (Errors.Is_Ok (Status), "could not open dependency replacement harness");
               Move_Task (To_String (Published.Tasks (1).Harness_Id), "accepted");
               Move_Task (To_String (Published.Tasks (2).Harness_Id), "accepted");
               Stores.Close (Harness);

               Draft.Tasks (1).Scope := To_Unbounded_String ("changed prerequisite execution scope");
               Draft.Fingerprint := To_Unbounded_String
                 (Improve.Stable_Digest (To_String (Draft.Fingerprint) & ":prerequisite-v2"));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Second := Improve.Storage.Save (Improve_State, Draft);
                  Improve.Storage.Close (Improve_State);
               end;
               Selected.Append (Second.Plan.Tasks (1).Id);
               declare Blocked : Boolean := False; begin
                  begin
                     Republished := Improve.Workflow.Publish
                       (To_String (Data.Target), Second.Plan, "auto", Existing => Mappings,
                        Selected_Task_Ids => Selected);
                  exception
                     when Error : Improve.Data_Error =>
                        Blocked := Ada.Strings.Fixed.Index
                          (Ada.Exceptions.Exception_Message (Error), "would strand published dependent") > 0;
                  end;
                  Assert (Blocked, "selective prerequisite replacement stranded its published dependent");
               end;
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 3 and then
                  Tasks.State_Of (Harness, To_String (Published.Tasks (1).Harness_Id)) = "accepted" and then
                  Tasks.State_Of (Harness, To_String (Published.Tasks (2).Harness_Id)) = "accepted",
                  "rejected selective replacement partially retired the native dependency graph");
               Stores.Close (Harness);

               Republished := Improve.Workflow.Publish
                 (To_String (Data.Target), Second.Plan, "auto", Existing => Mappings);
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               declare Definition : Records.Item; begin
                  Tasks.Definition
                    (Harness, To_String (Republished.Tasks (2).Harness_Id), Definition, Status);
                  Assert
                    (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 5 and then
                     Tasks.State_Of (Harness, To_String (Published.Tasks (1).Harness_Id)) = "cancelled" and then
                     Tasks.State_Of (Harness, To_String (Published.Tasks (2).Harness_Id)) = "cancelled" and then
                     Records.Get (Definition, "depends_on") = To_String (Republished.Tasks (1).Harness_Id),
                     "full-plan replacement did not migrate the concrete native dependency edge");
               end;
               Stores.Close (Harness);
               for Value of Republished.Tasks loop
                  Mappings.Append
                    (Improve.Storage.Publication_Record'
                       (Value.Improve_Id, Value.Harness_Id, Value.Origin, Value.Contract,
                        Value.State, Second.Plan.Revision));
               end loop;
               Stores.Open (Harness, To_String (Data.Target), Recovery, Status);
               Move_Task (To_String (Republished.Tasks (1).Harness_Id), "accepted");
               Move_Task (To_String (Republished.Tasks (2).Harness_Id), "accepted");
               declare Work : constant Tasks.Next_Work := Tasks.Next_Work_Of (Harness); begin
                  Assert
                    (Work.Runnable.Contains (To_String (Republished.Tasks (1).Harness_Id)) and then
                     Work.Blocked.Contains (To_String (Republished.Tasks (2).Harness_Id)),
                     "replacement dependent did not wait for its new prerequisite");
               end;
               Move_Task (To_String (Republished.Tasks (1).Harness_Id), "running");
               Move_Task (To_String (Republished.Tasks (1).Harness_Id), "verification");
               Move_Task (To_String (Republished.Tasks (1).Harness_Id), "complete", Gates_Passed => True);
               declare Work : constant Tasks.Next_Work := Tasks.Next_Work_Of (Harness); begin
                  Assert
                    (Work.Runnable.Contains (To_String (Republished.Tasks (2).Harness_Id)),
                     "replacement dependent did not become executable after its new prerequisite completed");
               end;
               Move_Task (To_String (Republished.Tasks (2).Harness_Id), "running");
               Stores.Close (Harness);

               declare Third_Draft : Improve.Model.Plan_Revision := Second.Plan; begin
                  Third_Draft.Tasks (1).Scope := To_Unbounded_String ("third prerequisite execution scope");
                  Third_Draft.Fingerprint := To_Unbounded_String
                    (Improve.Stable_Digest (To_String (Third_Draft.Fingerprint) & ":prerequisite-v3"));
                  declare Improve_State : Improve.Storage.Store; begin
                     Improve.Storage.Open (Improve_State, State, Writable => True);
                     Third := Improve.Storage.Save (Improve_State, Third_Draft);
                     Improve.Storage.Close (Improve_State);
                  end;
               end;
               declare Blocked : Boolean := False; begin
                  begin
                     Republished := Improve.Workflow.Publish
                       (To_String (Data.Target), Third.Plan, "auto", Existing => Mappings);
                  exception
                     when Error : Improve.Data_Error =>
                        Blocked := Ada.Strings.Fixed.Index
                          (Ada.Exceptions.Exception_Message (Error), "while native predecessor") > 0;
                  end;
                  Assert (Blocked, "running dependent did not block prerequisite contract replacement");
               end;
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 5 and then
                  Tasks.State_Of (Harness, To_String (Republished.Tasks (1).Harness_Id)) = "complete" and then
                  Tasks.State_Of (Harness, To_String (Republished.Tasks (2).Harness_Id)) = "running",
                  "blocked dependent migration partially changed the native dependency graph");
               Stores.Close (Harness);
               Remove (Data);
            end;
         when Refresh_Reconciles_State =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("refresh_state");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : Improve.CLI.Outcome;
               Applied   : Improve.CLI.Outcome;
               Refreshed : Improve.CLI.Outcome;
               Mapping   : Improve.Storage.Publication_Record;
               Store     : Stores.Store;
               Recovery  : Stores.Recovery_Report;
               Change    : Stores.Transaction;
               Status    : Errors.Error_Info;
               Run       : Positive;
            begin
               Planned := Prepare_Verification_Plan (Data, State);
               Assert (Planned.Exit_Code = 0, "refresh fixture plan failed");
               Initialize_Harness (To_String (Data.Target));
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert (Applied.Exit_Code = 0, "refresh fixture publication failed");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Mapping := Improve.Storage.Publications (Improve_State, "PLAN-000001").First_Element;
                  Improve.Storage.Close (Improve_State);
               end;
               Stores.Open (Store, To_String (Data.Target), Recovery, Status);
               Assert (Errors.Is_Ok (Status), "refresh fixture harness open failed");
               Tasks.Move
                 (Store, Change, To_String (Mapping.Harness_Task_Id), "accepted", "", Status => Status,
                  Actor => "improve-test");
               Assert (Errors.Is_Ok (Status), "refresh fixture task acceptance failed");
               Stores.Commit (Store, Change, Status);
               Assert (Errors.Is_Ok (Status), "refresh fixture harness commit failed");
               Stores.Close (Store);
               Run := Publish_Followup (Data, Source => "source-remediated", Toolchain => "gnat-16.0");
               Refreshed := Improve.CLI.Execute
                 (Args ("refresh|--project|" & Id_Image (Data.Project) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Run > Data.Run and then Refreshed.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (Refreshed.Output), """command"":""refresh""") > 0,
                       "refresh command did not complete: " & To_String (Refreshed.Errors));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Mapping := Improve.Storage.Publications (Improve_State, "PLAN-000001").First_Element;
                  Improve.Storage.Close (Improve_State);
               end;
               Assert (To_String (Mapping.State) = "accepted", "refresh did not synchronize harness state");
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
end Improve_Publication_Test_Suite;
