separate (Improve_Publication_Test_Suite)
procedure Run_Dependencies_Test (Item : in out Case_Test) is
begin
   case Item.Id is
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
               First_Map : Improve.State.Publication_Record;
               Next_Map  : Improve.State.Publication_Record;
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
               Mappings    : Improve.State.Publication_Vectors.Vector;
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
               Published := Improve.Workflow.Publish (To_String (Data.Target), "aunit", First.Plan, "auto");
               for Value of Published.Tasks loop
                  Mappings.Append
                    (Improve.State.Publication_Record'
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
               declare
                  Blocked : Boolean := False;
               begin
                  begin
                     Republished := Improve.Workflow.Publish
                       (To_String (Data.Target), "aunit", Second.Plan, "auto", Existing => Mappings,
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
                 (To_String (Data.Target), "aunit", Second.Plan, "auto", Existing => Mappings);
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
                    (Improve.State.Publication_Record'
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
               declare
                  Blocked : Boolean := False;
                  Detail  : Unbounded_String;
               begin
                  begin
                     Republished := Improve.Workflow.Publish
                       (To_String (Data.Target), "aunit", Third.Plan, "auto", Existing => Mappings);
                  exception
                     when Error : Improve.Data_Error =>
                        Detail := To_Unbounded_String (Ada.Exceptions.Exception_Message (Error));
                        Blocked := Ada.Strings.Fixed.Index
                          (Ada.Exceptions.Exception_Message (Error), "while native predecessor") > 0;
                  end;
                  Assert
                    (Blocked,
                     "running dependent did not block prerequisite contract replacement: " & To_String (Detail));
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
      when others =>
         raise Program_Error with "case routed to the wrong publication test group";
   end case;
end Run_Dependencies_Test;
