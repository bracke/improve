separate (Improve_Publication_Test_Suite)
procedure Run_Lifecycle_Test (Item : in out Case_Test) is
begin
   case Item.Id is
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
      when others =>
         raise Program_Error with "case routed to the wrong publication test group";
   end case;
end Run_Lifecycle_Test;
