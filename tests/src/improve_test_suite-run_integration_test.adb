separate (Improve_Test_Suite)
procedure Run_Integration_Test (Item : in out Case_Test) is
begin
   case Item.Id is
         when Plan_Dry_Run_CLI =>
            declare
               Data   : constant Fixture := Build_Fixture ("plan_cli");
               Result : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute
                   (Args ("plan|--dry-run|--database|" & To_String (Data.Database) & "|--project|" &
                          Id_Image (Data.Project) & "|--format|json"));
            begin
               Assert (Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index (To_String (Result.Output),
                       """dry_run"":true") > 0 and then Ada.Strings.Fixed.Index (To_String (Result.Output),
                       "Investigate missing coverage evidence") > 0,
                       "plan JSON dry-run failed: " & To_String (Result.Errors));
               for Level in Improve.Config.Severity_Level loop
                  declare
                     Settings : Improve.Config.Settings := Improve.Config.Defaults;
                     Planned  : Improve.Operations.Planning.Generation_Result;
                  begin
                     Settings.Minimum_Severity := Level;
                     Planned := Improve.Operations.Planning.Generate
                       (To_String (Data.Directory) & "/unused.db", To_String (Data.Database),
                        Id_Image (Data.Project), 0, Settings, Dry_Run => True);
                     Assert (Planned.Plan.Baseline.Run_Id = Data.Run, "severity-specific planning changed the run");
                  end;
               end loop;
               declare
                  Settings : Improve.Config.Settings := Improve.Config.Defaults;
                  Rejected : Boolean := False;
               begin
                  Settings.Maximum_Output_Items := 1;
                  begin
                     declare
                        Planned : constant Improve.Operations.Planning.Generation_Result :=
                          Improve.Operations.Planning.Generate
                            (To_String (Data.Directory) & "/bounded.db", To_String (Data.Database),
                             Id_Image (Data.Project), 0, Settings, Dry_Run => True);
                        pragma Unreferenced (Planned);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Data_Error => Rejected := True;
                  end;
                  Assert (Rejected, "planning ignored output.maximum_output_items");
               end;
               declare
                  Rejected : Boolean := False;
               begin
                  begin
                     declare
                        Planned : constant Improve.Operations.Planning.Generation_Result :=
                          Improve.Operations.Planning.Generate
                            (To_String (Data.Directory), To_String (Data.Database), Id_Image (Data.Project), 0,
                             Improve.Config.Defaults, Dry_Run => False);
                        pragma Unreferenced (Planned);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Dependency_Error | Improve.Data_Error => Rejected := True;
                  end;
                  Assert (Rejected, "planning accepted a directory as its state database");
               end;
               Remove (Data);
            end;
         when Persistent_Plan_Roundtrip =>
            declare
               Data  : constant Fixture := Build_Fixture ("plan_roundtrip");
               State : constant String := To_String (Data.Directory) & "/improve.db";
               Create_Result : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute
                   (Args ("plan|--database|" & To_String (Data.Database) & "|--state|" & State & "|--project|" &
                          Id_Image (Data.Project) & "|--format|json"));
               Show_Result : Improve.CLI.Outcome;
               List_Result : Improve.CLI.Outcome;
            begin
               Assert (Create_Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (Create_Result.Output), """plan_id"":""PLAN-000001""") > 0,
                       "persistent plan creation failed: " & To_String (Create_Result.Errors));
               Show_Result := Improve.CLI.Execute (Args ("plan|show|PLAN-000001|--state|" & State & "|--format|json"));
               Assert (Show_Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (Show_Result.Output), """stored"":true") > 0 and then
                       Ada.Strings.Fixed.Index (To_String (Show_Result.Output), "fixture-manifest") > 0,
                       "stored plan did not round-trip: " & To_String (Show_Result.Errors));
               List_Result := Improve.CLI.Execute
                 (Args ("plan|list|--database|" & To_String (Data.Database) & "|--state|" & State & "|--project|" &
                        Id_Image (Data.Project) & "|--format|json"));
               Assert (List_Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (List_Result.Output), """task_count"":3") > 0,
                       "stored plan listing failed: " & To_String (List_Result.Errors));
               Remove (Data);
            end;
         when Repeated_Plan_Idempotent =>
            declare
               Data  : constant Fixture := Build_Fixture ("plan_repeat");
               State : constant String := To_String (Data.Directory) & "/improve.db";
               Command : constant String :=
                 "plan|--database|" & To_String (Data.Database) & "|--state|" & State & "|--project|" &
                 Id_Image (Data.Project) & "|--format|json";
               First  : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args (Command));
               Second : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args (Command));
               Store  : Improve.Storage.Store;
            begin
               Assert (First.Exit_Code = 0 and then Second.Exit_Code = 0, "repeated planning failed");
               Improve.Storage.Open (Store, State, Writable => False);
               declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
                 Improve.Storage.List_All (Store);
               begin
                  Assert (Values.Length = 1 and then Values.First_Element.Revision = 1,
                          "repeated planning duplicated the plan revision");
               end;
               Improve.Storage.Close (Store);
               Remove (Data);
            end;
         when Persisted_Dependency_Translation =>
            declare
               Data    : constant Fixture := Build_Fixture ("dependency_translation");
               State   : constant String := To_String (Data.Directory) & "/improve.db";
               Quality : Improve.Source.Repository;
               Store   : Improve.Storage.Store;
            begin
               Improve.Source.Open (Quality, To_String (Data.Database));
               declare
                  Project  : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Quality, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Quality, Project);
                  Draft    : Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate
                      (Selected, Improve.Findings.Normalize (Selected),
                       Improve.Operations.Planning_Policy (Improve.Config.Defaults));
               begin
                  Draft.Tasks (2).Dependencies.Append (Draft.Tasks (1).Id);
                  Improve.Storage.Open (Store, State, Writable => True);
                  declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Draft); begin
                     Assert (To_String (Saved.Plan.Tasks (2).Dependencies.First_Element) = "IMP-000001",
                             "persisted dependency did not use the assigned Improve task identity");
                  end;
                  Improve.Storage.Close (Store);
               end;
               Improve.Source.Close (Quality);
               Remove (Data);
            end;
         when Read_Only_Does_Not_Initialize =>
            declare
               Directory : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-read-only");
               State     : constant String := Directory & "/missing.db";
               Result    : Improve.CLI.Outcome;
            begin
               Result := Improve.CLI.Execute (Args ("plan|show|PLAN-000001|--state|" & State));
               Assert (Result.Exit_Code = Improve.CLI.Unavailable_Exit and then not Ada.Directories.Exists (State),
                       "read-only plan inspection initialized missing state");
               Project_Tools.Files.Delete_Tree (Directory);
            end;
         when Storage_Finalizes_On_Error =>
            declare
               Directory : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-finalize");
               State     : constant String := Directory & "/state.db";
               Rejected  : Boolean := False;
            begin
               declare Store : Improve.Storage.Store; begin
                  Improve.Storage.Open (Store, State, Writable => True);
               end;
               begin
                  declare
                     Store : Improve.Storage.Store;
                     Plan  : Improve.Model.Plan_Revision;
                  begin
                     Improve.Storage.Open (Store, State, Writable => False);
                     Plan := Improve.Storage.Load (Store, "PLAN-999999");
                     Assert (To_String (Plan.Plan_Id) = "", "unexpected missing plan identity");
                  end;
               exception
                  when Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "invalid storage lookup did not fail");
               declare Store : Improve.Storage.Store; begin
                  Improve.Storage.Open (Store, State, Writable => True);
                  Improve.Storage.Close (Store);
               end;
               Project_Tools.Files.Delete_Tree (Directory);
            end;
         when Plan_Approval_Required =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("approval_required");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Applied   : Improve.CLI.Outcome;
               Replanned : Improve.CLI.Outcome;
               Run       : Positive;
               Harness   : Stores.Store;
               Status    : Errors.Error_Info;
            begin
               Assert (Planned.Exit_Code = 0, "approval fixture planning failed");
               Initialize_Harness (To_String (Data.Target));
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Applied.Exit_Code = Improve.CLI.Argument_Exit and then
                  Ada.Strings.Fixed.Index (To_String (Applied.Errors), "plan approve") > 0,
                  "pending review did not block publication");
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Is_Empty,
                  "rejected pending plan modified harness state");
               Stores.Close (Harness);
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert (Applied.Exit_Code = 0, "approved plan did not publish");
               Run := Publish_Followup (Data);
               Replanned := Improve.CLI.Execute
                 (Args ("plan|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Replanned.Exit_Code = 0, "approval fixture replanning failed");
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Applied.Exit_Code = Improve.CLI.Argument_Exit,
                  "new plan revision inherited prior approval");
               Remove (Data);
            end;
         when Current_Source_Staleness_Detected =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data    : constant Fixture := Build_Fixture ("source_stale");
               State   : constant String := To_String (Data.Directory) & "/improve.db";
               Planned : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Applied : Improve.CLI.Outcome;
               Harness : Stores.Store;
               Status  : Errors.Error_Info;
            begin
               Assert (Planned.Exit_Code = 0, "source-staleness fixture planning failed");
               Initialize_Harness (To_String (Data.Target));
               Approve_Latest (State);
               Project_Tools.Files.Write_Text_File
                 (To_String (Data.Target) & "/alire.toml",
                  "name = ""changed_after_measurement""" & ASCII.LF &
                  "version = ""0.1.0-dev""" & ASCII.LF &
                  "licenses = ""MIT""" & ASCII.LF);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Applied.Exit_Code = Improve.CLI.Failure_Exit and then
                  Ada.Strings.Fixed.Index (To_String (Applied.Errors), "current project source differs") > 0,
                  "unmeasured current source change did not block publication");
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Is_Empty,
                  "stale-source rejection modified harness state");
               Stores.Close (Harness);
               Remove (Data);
            end;
         when Measurement_Source_Mismatch_Blocks_Plan =>
            declare
               Data   : constant Fixture := Build_Fixture ("measurement_source_mismatch");
               State  : constant String := To_String (Data.Directory) & "/improve.db";
               Result : Improve.CLI.Outcome;
            begin
               Project_Tools.Files.Write_Text_File
                 (To_String (Data.Target) & "/new_source.adb",
                  "procedure New_Source is begin null; end New_Source;" & ASCII.LF);
               Result := Improve.CLI.Execute
                 (Args ("plan|--database|" & To_String (Data.Database) & "|--state|" & State & "|--project|" &
                        Id_Image (Data.Project) & "|--format|json"));
               Assert
                 (Result.Exit_Code = Improve.CLI.Failure_Exit and then
                  Ada.Strings.Fixed.Index (To_String (Result.Errors), "does not match the selected assessment") > 0 and
                  then not Ada.Directories.Exists (State),
                  "planning silently combined measured evidence with unmeasured source");
               Remove (Data);
            end;
         when Quality_Database_Identity_Rejected =>
            declare
               First   : constant Fixture := Build_Fixture ("identity_first");
               Second  : constant Fixture := Build_Fixture ("identity_second");
               State   : constant String := To_String (First.Directory) & "/improve.db";
               Planned : constant Improve.CLI.Outcome := Prepare_Verification_Plan (First, State);
               Applied : Improve.CLI.Outcome;
               Verified : Improve.CLI.Outcome;
               Expected : constant Improve.Model.Project_Reference := Draft_For (First).Project;
               Actual   : Improve.Model.Project_Reference := Expected;
               Root_Rejected : Boolean := False;
            begin
               Assert (Planned.Exit_Code = 0, "database-identity fixture plan failed");
               Initialize_Harness (To_String (First.Target));
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Second.Database) & "|--state|" & State &
                        "|--format|json"));
               Verified := Improve.CLI.Execute
                 (Args ("verify|--task|IMP-000001|--database|" & To_String (Second.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Applied.Exit_Code = Improve.CLI.Failure_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Applied.Errors), "database does not own the stored plan") > 0,
                  "apply accepted a same-numbered project from another quality database");
               Assert
                 (Verified.Exit_Code = Improve.CLI.Failure_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Verified.Errors), "database does not own the stored plan") > 0,
                  "verification accepted a same-numbered project from another quality database");
               Actual.Path := Second.Target;
               begin
                  Improve.Operations.Require_Project_Identity (Expected, Actual);
               exception
                  when Improve.Data_Error => Root_Rejected := True;
               end;
               Assert (Root_Rejected, "project identity accepted a different canonical project root");
               Remove (First);
               Remove (Second);
            end;
         when Quality_Database_Histories_Isolated =>
            declare
               First       : constant Fixture := Build_Fixture ("history_first");
               Second      : constant Fixture := Build_Fixture ("history_second");
               State_Path  : constant String := To_String (First.Directory) & "/improve.db";
               First_Plan  : constant Improve.CLI.Outcome := Prepare_Verification_Plan (First, State_Path);
               Second_Plan : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Second, State_Path);
               Store       : Improve.Storage.Store;
               Second_Task : Unbounded_String;
               Listed      : Improve.CLI.Outcome;
               Rejected    : Improve.CLI.Outcome;
            begin
               Assert
                 (First.Project = Second.Project and then First_Plan.Exit_Code = 0 and then Second_Plan.Exit_Code = 0,
                  "same-numbered database history fixture did not plan");
               Improve.Storage.Open (Store, State_Path, Writable => False);
               Assert
                 (Improve.Storage.List_All (Store).Length = 2 and then
                  Improve.Storage.List
                    (Store, Draft_For (First).Project).Length = 1 and then
                  Improve.Storage.List
                    (Store, Draft_For (Second).Project).Length = 1,
                  "same numeric project IDs shared remediation history");
               Second_Task := Improve.Storage.Load (Store, "PLAN-000002").Tasks.First_Element.Id;
               Improve.Storage.Close (Store);
               Listed := Improve.CLI.Execute
                 (Args ("tasks|--project|" & Id_Image (First.Project) & "|--database|" &
                        To_String (First.Database) & "|--state|" & State_Path & "|--format|json"));
               Rejected := Improve.CLI.Execute
                 (Args ("tasks|--task|" & To_String (Second_Task) & "|--project|" & Id_Image (First.Project) &
                        "|--database|" & To_String (First.Database) & "|--state|" & State_Path & "|--format|json"));
               Assert
                 (Listed.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Listed.Output), """plan_id"":""PLAN-000001""") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Listed.Output), "PLAN-000002") = 0,
                  "tasks --project mixed equal numeric IDs from independent databases");
               Assert
                 (Rejected.Exit_Code = Improve.CLI.Argument_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Rejected.Errors), "does not belong to selected project") > 0,
                  "tasks --task accepted ownership from another quality database");
               Remove (First);
               Remove (Second);
            end;
         when Publication_Policy_Change_Rejected =>
            declare
               Data    : constant Fixture := Build_Fixture ("publication_policy");
               State   : constant String := To_String (Data.Directory) & "/improve.db";
               Planned : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Baseline_Source : constant String := To_String (Draft_For (Data).Baseline.Source_Id);
               Run     : Positive;
               Applied : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "publication-policy fixture plan failed");
               Initialize_Harness (To_String (Data.Target));
               Approve_Latest (State);
               Run := Publish_Followup (Data, Policy => "policy-b", Source => Baseline_Source);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Run > Data.Run and then Applied.Exit_Code = Improve.CLI.Failure_Exit and then
                  Ada.Strings.Fixed.Index (To_String (Applied.Errors), "quality policy changed") > 0,
                  "publication accepted a newer incompatible quality policy: " &
                    To_String (Applied.Errors) & To_String (Applied.Output));
               declare
                  Store  : Model_Runner.Framework.Stores.Store;
                  Status : Model_Runner.Errors.Error_Info;
               begin
                  Model_Runner.Framework.Stores.Open_To_Read (Store, To_String (Data.Target), Status);
                  Assert
                    (Model_Runner.Errors.Is_Ok (Status) and then
                     Model_Runner.Framework.Tasks.List (Store).Is_Empty,
                     "policy-change rejection modified harness state");
                  Model_Runner.Framework.Stores.Close (Store);
               end;
               Remove (Data);
            end;
         when Publication_Baseline_Mutation_Rejected =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("publication_replaced_baseline");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Baseline  : constant Positive := Publish_Followup
                 (Data, Structure_State => Structure_Failing);
               Planned   : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute
                   (Args ("plan|--database|" & To_String (Data.Database) & "|--state|" & State &
                          "|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Baseline) &
                          "|--format|json"));
               Applied   : Improve.CLI.Outcome;
               Harness   : Stores.Store;
               Status    : Errors.Error_Info;
            begin
               Assert (Planned.Exit_Code = 0, "replacement-baseline fixture planning failed");
               Initialize_Harness (To_String (Data.Target));
               Approve_Latest (State);
               Replace_Assessment_Evidence (To_String (Data.Database), Baseline);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Applied.Exit_Code = Improve.CLI.Failure_Exit and then
                  Ada.Strings.Fixed.Index (To_String (Applied.Errors), "no longer matches") > 0,
                  "publication accepted a mutated exact assessment baseline");
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Is_Empty,
                  "replaced-baseline rejection modified harness state");
               Stores.Close (Harness);
               Remove (Data);
            exception
               when others =>
                  Remove (Data);
                  raise;
            end;
         when Historical_Task_Lookup =>
            declare
               Data       : constant Fixture := Build_Fixture ("historical_task");
               State      : constant String := To_String (Data.Directory) & "/improve.db";
               Planned    : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Run        : Positive;
               Replanned  : Improve.CLI.Outcome;
               Inspected  : Improve.CLI.Outcome;
               Verified   : Improve.CLI.Outcome;
               Shown      : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "historical-task fixture planning failed");
               Run := Publish_Followup (Data);
               Replanned := Improve.CLI.Execute
                 (Args ("plan|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Replanned.Exit_Code = 0, "historical-task fixture replanning failed");
               Inspected := Improve.CLI.Execute
                 (Args ("tasks|--task|IMP-000001|--revision|1|--state|" & State & "|--format|json"));
               Assert
                 (Inspected.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Inspected.Output), "IMP-000001") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Inspected.Output), """verification_freshness"":""unknown""") > 0,
                  "task omitted from latest revision is not inspectable");
               Verified := Improve.CLI.Execute
                 (Args ("verify|--task|IMP-000001|--revision|1|--run|" & Id_Image (Run) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert
                 (Verified.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Verified.Output), """outcome"":""verified""") > 0,
                  "historical task cannot be independently verified");
               Shown := Improve.CLI.Execute
                 (Args ("plan|show|PLAN-000001|--revision|1|--state|" & State & "|--format|json"));
               Assert
                 (Shown.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Shown.Output), """revision"":1") > 0,
                  "exact historical plan revision cannot be inspected");
               Remove (Data);
            end;
      when others =>
         raise Program_Error with "non-integration case routed to integration test subunit";
   end case;
end Run_Integration_Test;
