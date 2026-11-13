separate (Improve_Publication_Test_Suite)
procedure Run_Refresh_Test (Item : in out Case_Test) is
begin
   case Item.Id is
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
               Stores.Open (Store, To_String (Data.Target), Recovery, Status);
               Assert (Errors.Is_Ok (Status), "refresh fixture could not hold the harness writer lock");
               Refreshed := Improve.CLI.Execute
                 (Args ("refresh|--project|" & Id_Image (Data.Project) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Stores.Close (Store);
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
         when Refresh_Rejects_Definition_Drift =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data    : constant Fixture := Build_Fixture ("refresh_definition_drift");
               State   : constant String := To_String (Data.Directory) & "/improve.db";
               Planned : Improve.CLI.Outcome;
               Applied : Improve.CLI.Outcome;
               Mapping : Improve.Storage.Publication_Record;
               Store   : Stores.Store;
               Recovery : Stores.Recovery_Report;
               Change  : Stores.Transaction;
               Fields  : Tasks.Field_Map;
               Status  : Errors.Error_Info;
            begin
               Planned := Prepare_Verification_Plan (Data, State);
               Assert (Planned.Exit_Code = 0, "definition-drift fixture plan failed");
               Initialize_Harness (To_String (Data.Target));
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State));
               Assert (Applied.Exit_Code = 0, "definition-drift fixture publication failed");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Mapping := Improve.Storage.Publications (Improve_State, "PLAN-000001").First_Element;
                  Improve.Storage.Close (Improve_State);
               end;
               Stores.Open (Store, To_String (Data.Target), Recovery, Status);
               Assert (Errors.Is_Ok (Status), "definition-drift harness open failed");
               Fields.Include ("acceptance", "acceptance changed outside Improve");
               Tasks.Revise (Store, Change, To_String (Mapping.Harness_Task_Id), Fields, Status);
               Assert (Errors.Is_Ok (Status), "definition-drift fixture could not revise native task");
               Stores.Commit (Store, Change, Status);
               Assert (Errors.Is_Ok (Status), "definition-drift fixture could not commit native task revision");
               Stores.Close (Store);
               declare
                  Refreshed : constant Improve.CLI.Outcome := Improve.CLI.Execute
                    (Args ("refresh|--project|" & Id_Image (Data.Project) & "|--database|" &
                           To_String (Data.Database) & "|--state|" & State));
               begin
                  Assert
                    (Refreshed.Exit_Code = Improve.CLI.Failure_Exit and then
                     Ada.Strings.Fixed.Index
                       (To_String (Refreshed.Errors), "native task definition differs") > 0,
                     "refresh accepted a native task whose execution definition drifted");
               end;
               Remove (Data);
            end;
      when others =>
         raise Program_Error with "case routed to the wrong publication test group";
   end case;
end Run_Refresh_Test;
