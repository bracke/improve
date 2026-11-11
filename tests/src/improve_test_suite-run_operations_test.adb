separate (Improve_Test_Suite)
procedure Run_Operations_Test (Item : in out Case_Test) is
begin
   case Item.Id is
         when Tasks_CLI_Golden =>
            declare
               Data     : constant Fixture := Build_Fixture ("tasks_golden", Harness_Project => True);
               State    : constant String := To_String (Data.Directory) & "/improve.db";
               Planned  : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Result   : Improve.CLI.Outcome;
               Expected : constant String :=
                 "Remediation tasks" & Character'Val (10) &
                 "ID  Harness  Status  Title" & Character'Val (10) &
                 "IMP-000001  -  proposed  Repair the Alire manifest" & Character'Val (10) &
                 "IMP-000002  -  proposed  Restore toolchain identification" & Character'Val (10) &
                 "IMP-000003  -  proposed  Investigate missing coverage evidence" & Character'Val (10);
            begin
               Assert (Planned.Exit_Code = 0, "tasks golden fixture plan failed");
               Result := Improve.CLI.Execute
                 (Args ("tasks|--project|" & Id_Image (Data.Project) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--color|never"));
               Assert (Result.Exit_Code = 0 and then To_String (Result.Output) = Expected,
                       "terminal task output changed unexpectedly: " & To_String (Result.Errors));
               Must_Reject ("tasks", "requires --project or --task");
               Remove (Data);
            end;
         when Tasks_JSON_Filter =>
            declare
               Data    : constant Fixture := Build_Fixture ("tasks_json", Harness_Project => True);
               State   : constant String := To_String (Data.Directory) & "/improve.db";
               Planned : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Result  : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "tasks JSON fixture plan failed");
               Result := Improve.CLI.Execute
                 (Args ("tasks|--task|IMP-000001|--state|" & State & "|--format|json|--color|always"));
               Assert (Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (Result.Output), """command"":""tasks""") > 0 and then
                         Ada.Strings.Fixed.Index (To_String (Result.Output), "IMP-000001") > 0 and then
                         Ada.Strings.Fixed.Index (To_String (Result.Output), "IMP-000002") = 0 and then
                         Ada.Strings.Fixed.Index (To_String (Result.Output), Character'Val (27) & "[") = 0,
                       "task JSON filtering or styling is invalid");
               Result := Improve.CLI.Execute
                 (Args ("tasks|--project|" & Id_Image (Data.Project) & "|--status|not-a-status|--database|" &
                        To_String (Data.Database) & "|--state|" & State));
               Assert (Result.Exit_Code = Improve.CLI.Argument_Exit and then Length (Result.Output) = 0,
                       "invalid task status did not return exit 2");
               Remove (Data);
            end;
         when Status_Project_And_All =>
            declare
               Data    : constant Fixture := Build_Fixture ("status", Harness_Project => True);
               State   : constant String := To_String (Data.Directory) & "/improve.db";
               Planned : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               One     : Improve.CLI.Outcome;
               All_Of  : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "status fixture plan failed");
               One := Improve.CLI.Execute
                 (Args ("status|--project|" & Id_Image (Data.Project) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               All_Of := Improve.CLI.Execute
                 (Args ("status|--all|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert (One.Exit_Code = 0 and then All_Of.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (One.Output), """baseline_run"":1") > 0 and then Ada.Strings.Fixed.Index
                         (To_String (One.Output), """latest_run"":1") > 0 and then Ada.Strings.Fixed.Index
                         (To_String (One.Output), """plan_count"":1") > 0 and then Ada.Strings.Fixed.Index
                         (To_String (One.Output), """unverified"":3") > 0 and then Ada.Strings.Fixed.Index
                         (To_String (All_Of.Output), """command"":""status""") > 0,
                       "project or all-project status summary is invalid");
               Remove (Data);
            end;
         when Status_Verification_Freshness =>
            declare
               Data       : constant Fixture := Build_Fixture ("status_freshness", Harness_Project => True);
               State      : constant String := To_String (Data.Directory) & "/improve.db";
               Planned    : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Verified   : Positive;
               Latest     : Positive;
               Checked    : Improve.CLI.Outcome;
               JSON_View  : Improve.CLI.Outcome;
               Text_View  : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "status-freshness fixture plan failed");
               Verified := Publish_Followup (Data);
               Checked := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Verified) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Checked.Exit_Code = 0, "status-freshness verification failed");
               Latest := Publish_Followup (Data, Structure_State => Structure_Failing);
               JSON_View := Improve.CLI.Execute
                 (Args ("status|--project|" & Id_Image (Data.Project) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Text_View := Improve.CLI.Execute
                 (Args ("status|--project|" & Id_Image (Data.Project) & "|--database|" &
                        To_String (Data.Database) & "|--state|" & State & "|--color|never"));
               Assert
                 (JSON_View.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """latest_run"":" & Id_Image (Latest)) > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """project_quality"":""unverified""") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """project_verification_run"":" & Id_Image (Verified)) > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """project_verification_current"":false") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """previous_project_quality"":""verified""") > 0,
                  "status presented historical verification as current quality");
               Assert
                 (Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """quality_outcome"":""verified""") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """verification_run"":" & Id_Image (Verified)) > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """verification_current"":false") > 0,
                  "task status did not distinguish historical verification from current evidence");
               Assert
                 (Ada.Strings.Fixed.Index (To_String (JSON_View.Output), """resolved"":0") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """previously_resolved"":3") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (JSON_View.Output), """unverified"":0") > 0,
                  "finding summary reused historical resolution as a current result");
               Assert
                 (Text_View.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Text_View.Output), "Project quality: unverified") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Text_View.Output),
                     "Last project verification assessment: " & Id_Image (Verified)) > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Text_View.Output), "Previous project result: verified") > 0,
                  "terminal status did not label historical verification");
               Remove (Data);
            end;
         when Status_All_Mixed_Freshness =>
            declare
               First       : constant Fixture := Build_Fixture ("status_all_mixed", Harness_Project => True);
               Second      : constant Fixture := Add_Fixture_Project (First, "second");
               State       : constant String := To_String (First.Directory) & "/improve.db";
               First_Plan  : constant Improve.CLI.Outcome := Prepare_Verification_Plan (First, State);
               Second_Plan : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Second, State);
               First_Run   : Positive;
               First_Latest : Positive;
               Second_Run  : Positive;
               Checked     : Improve.CLI.Outcome;
               All_Of      : Improve.CLI.Outcome;
            begin
               Assert
                 (First_Plan.Exit_Code = 0 and then Second_Plan.Exit_Code = 0,
                  "mixed-freshness plans failed");
               First_Run := Publish_Followup (First);
               Checked := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (First.Project) & "|--run|" & Id_Image (First_Run) &
                        "|--database|" & To_String (First.Database) & "|--state|" & State & "|--format|json"));
               Assert (Checked.Exit_Code = 0, "first mixed-freshness verification failed");
               First_Latest := Publish_Followup (First, Structure_State => Structure_Failing);
               Second_Run := Publish_Followup (Second);
               Checked := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Second.Project) & "|--run|" & Id_Image (Second_Run) &
                        "|--database|" & To_String (Second.Database) & "|--state|" & State & "|--format|json"));
               Assert (Checked.Exit_Code = 0, "second mixed-freshness verification failed");
               All_Of := Improve.CLI.Execute
                 (Args ("status|--all|--database|" & To_String (First.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (All_Of.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (All_Of.Output), """latest_run"":" & Id_Image (First_Latest) &
                     ",""plan_count"":1,""plan_quality"":""unverified""") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (All_Of.Output), """latest_run"":" & Id_Image (Second_Run) &
                     ",""plan_count"":1,""plan_quality"":""verified""") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (All_Of.Output), """project_verification_run"":" & Id_Image (First_Run) &
                     ",""project_verification_current"":false") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (All_Of.Output), """project_verification_run"":" & Id_Image (Second_Run) &
                     ",""project_verification_current"":true") > 0,
                  "status --all did not preserve per-project verification freshness");
               Remove (First);
            end;
         when Interrupted_Publication_Recovery =>
            declare
               Data      : constant Fixture := Build_Fixture ("recover", Harness_Project => True);
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Plan      : Improve.Model.Plan_Revision;
               Task_Ids  : Improve.Model.UString_Vectors.Vector;
               Operation : Positive;
               pragma Unreferenced (Operation);
               First     : Improve.CLI.Outcome;
               Second    : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "recovery fixture plan failed");
               Initialize_Harness (To_String (Data.Target));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  for Spec of Plan.Tasks loop Task_Ids.Append (Spec.Id); end loop;
                  Operation := Improve.Storage.Begin_Publication (Improve_State, Plan, Task_Ids);
                  Improve.Storage.Close (Improve_State);
               end;
               declare Published : constant Improve.Workflow.Publication_Result :=
                 Improve.Workflow.Publish (To_String (Plan.Project.Path), Plan, "auto");
               begin
                  Assert (Published.Tasks.Length = 3,
                          "interrupted recovery fixture did not commit harness tasks");
               end;
               Project_Tools.Files.Write_Text_File
                 (To_String (Data.Target) & "/after_harness_commit.adb",
                  "procedure After_Harness_Commit is begin null; end After_Harness_Commit;" & ASCII.LF);
               First := Improve.CLI.Execute (Args ("recover|--state|" & State & "|--format|json"));
               Second := Improve.CLI.Execute (Args ("recover|--state|" & State & "|--format|json"));
               Assert (First.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (First.Output), """operations_recovered"":1") > 0 and then
                         Ada.Strings.Fixed.Index (To_String (First.Output), """tasks_recovered"":3") > 0,
                       "interrupted publication was not recovered");
               Assert (Second.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (Second.Output), """operations_recovered"":0") > 0,
                       "repeated recovery was not idempotent");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Assert (Improve.Storage.Pending_Publications (Improve_State).Is_Empty and then
                            Improve.Storage.Publications (Improve_State, "PLAN-000001").Length = 3,
                          "recovery did not durably complete mappings and journal state");
                  Improve.Storage.Close (Improve_State);
               end;
               Remove (Data);
            end;
         when Recovery_Rejects_Stale_Uncommitted =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("recover_stale", Harness_Project => True);
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Plan      : Improve.Model.Plan_Revision;
               Task_Ids  : Improve.Model.UString_Vectors.Vector;
               Operation : Positive;
               Result    : Improve.CLI.Outcome;
               Harness   : Stores.Store;
               Status    : Errors.Error_Info;
               pragma Unreferenced (Operation);
            begin
               Assert (Planned.Exit_Code = 0, "stale recovery fixture plan failed");
               Initialize_Harness (To_String (Data.Target));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  Improve.Storage.Approve (Improve_State, "PLAN-000001", Plan.Revision);
                  for Spec of Plan.Tasks loop Task_Ids.Append (Spec.Id); end loop;
                  Operation := Improve.Storage.Begin_Publication (Improve_State, Plan, Task_Ids);
                  Improve.Storage.Close (Improve_State);
               end;
               Project_Tools.Files.Write_Text_File
                 (To_String (Data.Target) & "/stale_before_commit.adb",
                  "procedure Stale_Before_Commit is begin null; end Stale_Before_Commit;" & ASCII.LF);
               Result := Improve.CLI.Execute (Args ("recover|--state|" & State & "|--format|json"));
               Assert
                 (Result.Exit_Code = Improve.CLI.Failure_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Result.Errors), "operation retained") > 0,
                  "recovery replayed stale uncommitted publication work");
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Is_Empty,
                  "stale recovery created native tasks");
               Stores.Close (Harness);
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Assert
                    (Improve.Storage.Pending_Publications (Improve_State).Length = 1,
                     "stale recovery did not retain its pending operation");
                  Improve.Storage.Close (Improve_State);
               end;
               Remove (Data);
            end;
         when Published_Task_Reused_Across_Revisions =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data       : constant Fixture := Build_Fixture ("revision_reuse", Harness_Project => True);
               State      : constant String := To_String (Data.Directory) & "/improve.db";
               First_Plan : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Applied    : Improve.CLI.Outcome;
               Replanned  : Improve.CLI.Outcome;
               Run        : Positive;
               Old_Map    : Improve.Storage.Publication_Record;
               New_Map    : Improve.Storage.Publication_Record;
               Harness    : Stores.Store;
               Status     : Errors.Error_Info;
            begin
               Assert (First_Plan.Exit_Code = 0, "initial cross-revision plan failed");
               Initialize_Harness (To_String (Data.Target));
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert (Applied.Exit_Code = 0, "initial cross-revision publication failed");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  for Mapping of Improve.Storage.Publications (Improve_State, "PLAN-000001") loop
                     if To_String (Mapping.Improve_Task_Id) = "IMP-000001" then Old_Map := Mapping; exit; end if;
                  end loop;
                  Improve.Storage.Close (Improve_State);
               end;
               Run := Publish_Followup
                 (Data, Structure_State => Structure_Failing,
                  Source => Ada_Quality.Checks.Source_Fingerprint (To_String (Data.Target)));
               Replanned := Improve.CLI.Execute
                 (Args ("plan|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Replanned.Exit_Code = 0, "cross-revision replanning failed");
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Applied.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Applied.Output), """recovered"":true") > 0,
                  "unchanged cross-revision task was not recovered");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  for Mapping of Improve.Storage.Publications (Improve_State, "PLAN-000001") loop
                     if Mapping.Improve_Task_Id = Old_Map.Improve_Task_Id then New_Map := Mapping; exit; end if;
                  end loop;
                  Improve.Storage.Close (Improve_State);
               end;
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 3 and then
                  New_Map.Harness_Task_Id = Old_Map.Harness_Task_Id and then New_Map.Origin = Old_Map.Origin,
                  "unchanged task was duplicated or remapped across revisions");
               Stores.Close (Harness);
               Remove (Data);
            end;
         when Recovery_Uses_Exact_Revision =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("recovery_revision", Harness_Project => True);
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Plan      : Improve.Model.Plan_Revision;
               Task_Ids  : Improve.Model.UString_Vectors.Vector;
               Operation : Positive;
               Run       : Positive;
               Replanned : Improve.CLI.Outcome;
               Recovered : Improve.Recovery.Recovery_Report;
               Harness   : Stores.Store;
               Status    : Errors.Error_Info;
               pragma Unreferenced (Operation);
            begin
               Assert (Planned.Exit_Code = 0, "exact-revision recovery plan failed");
               Initialize_Harness (To_String (Data.Target));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  for Spec of Plan.Tasks loop Task_Ids.Append (Spec.Id); end loop;
                  Operation := Improve.Storage.Begin_Publication (Improve_State, Plan, Task_Ids);
                  Improve.Storage.Close (Improve_State);
               end;
               declare Published : constant Improve.Workflow.Publication_Result :=
                 Improve.Workflow.Publish (To_String (Data.Target), Plan, "auto");
               begin
                  Assert (Published.Tasks.Length = 3, "interrupted exact-revision publication failed");
               end;
               Run := Publish_Followup (Data);
               Replanned := Improve.CLI.Execute
                 (Args ("plan|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Replanned.Exit_Code = 0, "newer recovery fixture plan failed");
               Recovered := Improve.Recovery.Recover (State, "auto", Maximum => 10);
               Assert
                 (Recovered.Operations_Recovered = 1 and then Recovered.Tasks_Recovered = 3,
                  "recovery substituted a newer plan revision");
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 3,
                  "exact-revision recovery duplicated or lost native tasks");
               Stores.Close (Harness);
               Remove (Data);
            end;
         when Recovery_Limit_Enforced =>
            declare
               Data      : constant Fixture := Build_Fixture ("recover_limit", Harness_Project => True);
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Plan      : Improve.Model.Plan_Revision;
               All_Tasks : Improve.Model.UString_Vectors.Vector;
               One_Task  : Improve.Model.UString_Vectors.Vector;
               Rejected  : Boolean := False;
            begin
               Assert (Planned.Exit_Code = 0, "recovery limit fixture plan failed");
               declare Improve_State : Improve.Storage.Store; First, Second : Positive; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  for Spec of Plan.Tasks loop All_Tasks.Append (Spec.Id); end loop;
                  One_Task.Append (Plan.Tasks.First_Element.Id);
                  First := Improve.Storage.Begin_Publication (Improve_State, Plan, All_Tasks);
                  Second := Improve.Storage.Begin_Publication (Improve_State, Plan, One_Task);
                  Assert (First /= Second, "distinct recovery operations reused an identity");
                  Improve.Storage.Close (Improve_State);
               end;
               begin
                  declare
                     Report : constant Improve.Recovery.Recovery_Report :=
                       Improve.Recovery.Recover (State, "auto", Maximum => 1);
                     pragma Unreferenced (Report);
                  begin
                     null;
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "recovery operation limit was not enforced");
               Remove (Data);
            end;
         when Recover_Missing_State =>
            declare
               Path   : constant String := "/tmp/improve_phase8_missing_state.db";
               Result : Improve.CLI.Outcome;
            begin
               Project_Tools.Files.Delete_File_If_Present (Path);
               Result := Improve.CLI.Execute (Args ("recover|--state|" & Path & "|--format|json"));
               Assert (Result.Exit_Code = Improve.CLI.Unavailable_Exit and then Length (Result.Output) = 0 and then
                         not Project_Tools.Files.File_Exists (Path),
                       "recover initialized missing state or returned the wrong exit code");
            end;
         when Configuration_Bounds =>
            declare
               Path : constant String := "/tmp/improve_phase9_configuration.toml";

               procedure Write (Text : String) is
               begin
                  Project_Tools.Files.Write_Text_File
                    (Path, "schema_version = 1" & ASCII.LF & Text & ASCII.LF);
               end Write;

               procedure Reject (Text, Label : String) is
                  Rejected : Boolean := False;
               begin
                  Write (Text);
                  begin
                     declare Value : constant Improve.Config.Settings := Improve.Config.Load (Path);
                        pragma Unreferenced (Value);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Argument_Error => Rejected := True;
                  end;
                  Assert (Rejected, "configuration accepted invalid " & Label);
               end Reject;

               procedure Accept_Severity (Text : String; Expected : Improve.Config.Severity_Level) is
               begin
                  Write ("minimum_severity = """ & Text & """");
                  Assert (Improve.Config.Load (Path).Minimum_Severity = Expected,
                          "configuration did not preserve severity " & Text);
               end Accept_Severity;
            begin
               Write
                 ("database = ""quality.db""" & ASCII.LF &
                  "selection = ""latest_completed""" & ASCII.LF &
                  "minimum_severity = ""critical""" & ASCII.LF &
                  "maximum_tasks_per_plan = 7" & ASCII.LF &
                  "maximum_findings_per_task = 6" & ASCII.LF &
                  "allow_investigation_tasks = false" & ASCII.LF &
                  "require_review = false" & ASCII.LF &
                  "agent_max_context_bytes = 4096" & ASCII.LF &
                  "agent_max_file_bytes = 2048" & ASCII.LF &
                  "agent_max_response_bytes = 1024" & ASCII.LF &
                  "agent_timeout_seconds = 2" & ASCII.LF &
                  "maximum_output_items = 8" & ASCII.LF &
                  "maximum_recovery_operations = 9" & ASCII.LF &
                  "task_kind = ""remediation""" & ASCII.LF &
                  "publication = ""candidate""" & ASCII.LF &
                  "require_initialized_project = true" & ASCII.LF &
                  "require_fresh_measurement = false" & ASCII.LF &
                  "require_same_policy = false" & ASCII.LF &
                  "require_same_toolchain = true" & ASCII.LF &
                  "require_no_new_critical_findings = false" & ASCII.LF &
                  "format = ""json""" & ASCII.LF &
                  "color = ""never""");
               declare Value : constant Improve.Config.Settings := Improve.Config.Load (Path); begin
                  Assert
                    (Value.Minimum_Severity = Improve.Config.Critical and then
                     Value.Maximum_Tasks_Per_Plan = 7 and then Value.Maximum_Findings_Per_Task = 6 and then
                     not Value.Allow_Investigation_Tasks and then not Value.Require_Review and then
                     Value.Agent_Max_Context_Bytes = 4_096 and then Value.Maximum_Output_Items = 8 and then
                     Value.Maximum_Recovery_Operations = 9 and then Value.Format = Improve.Config.JSON_Format and then
                     Value.Color = Improve.Config.Color_Never and then Value.Require_Initialized and then
                     Ada.Strings.Fixed.Index (Improve.Config.Image (Value), "operations.maximum") > 0,
                     "valid nondefault configuration was not preserved");
               end;
               Project_Tools.Files.Write_Text_File (Path, "schema_version = 2" & ASCII.LF);
               begin
                  declare Value : constant Improve.Config.Settings := Improve.Config.Load (Path);
                     pragma Unreferenced (Value);
                  begin
                     Assert (False, "unsupported configuration schema was accepted");
                  end;
               exception
                  when Improve.Argument_Error => null;
               end;
               Accept_Severity ("info", Improve.Config.Info);
               Accept_Severity ("medium", Improve.Config.Medium);
               Accept_Severity ("high", Improve.Config.High);
               Reject ("selection = ""newest""", "selection");
               Reject ("database = """"", "empty database");
               Reject ("minimum_severity = ""urgent""", "severity");
               Reject ("task_kind = """"", "task kind");
               Reject ("publication = ""accepted""", "publication mode");
               Reject ("require_initialized_project = false", "initialized project policy");
               Reject ("format = ""yaml""", "output format");
               Reject ("color = ""sometimes""", "color policy");
               Reject ("maximum_tasks_per_plan = 0", "zero task limit");
               Reject ("maximum_tasks_per_plan = 10001", "task limit");
               Reject ("maximum_findings_per_task = 10001", "finding limit");
               Reject ("agent_max_context_bytes = 1000", "small agent context");
               Reject
                 ("agent_max_context_bytes = 1024" & ASCII.LF & "agent_max_file_bytes = 2048",
                  "agent file limit");
               Reject ("agent_max_response_bytes = 1048577", "agent response limit");
               Reject ("agent_timeout_seconds = 3601", "agent timeout");
               Reject ("maximum_output_items = 100001", "output item limit");
               Reject ("maximum_recovery_operations = 10001", "recovery limit");
               Reject ("require_review = maybe", "boolean");
               Project_Tools.Files.Delete_File_If_Present (Path);
            end;
         when Operational_Terminal_Paths =>
            declare
               Data    : constant Fixture := Build_Fixture ("terminal_paths", Harness_Project => True);
               State   : constant String := To_String (Data.Directory) & "/improve.db";
               Planned : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Result  : Improve.CLI.Outcome;
               Commands : Improve.Model.UString_Vectors.Vector;
               Tasks_Limited  : Boolean := False;
               Status_Limited : Boolean := False;
            begin
               Assert (Planned.Exit_Code = 0, "terminal-path fixture planning failed");
               begin
                  declare
                     Views : constant Improve.Tasks.View_Vectors.Vector :=
                       Improve.Operations.Inspection.Tasks
                         (State, To_String (Data.Database), Id_Image (Data.Project), "", 0, "all", 1);
                     pragma Unreferenced (Views);
                  begin
                     null;
                  end;
               exception
                  when Improve.Data_Error => Tasks_Limited := True;
               end;
               begin
                  declare
                     Values : constant Improve.Tasks.Status_Vectors.Vector :=
                       Improve.Operations.Inspection.Status
                         (State, To_String (Data.Database), Id_Image (Data.Project), False, 1);
                     pragma Unreferenced (Values);
                  begin
                     null;
                  end;
               exception
                  when Improve.Data_Error => Status_Limited := True;
               end;
               Assert
                 (Tasks_Limited and then Status_Limited,
                  "inspection limits did not reject oversized task materialization");
               Initialize_Harness (To_String (Data.Target));
               Commands.Append
                 (To_Unbounded_String
                    ("plan|list|--project|" & Id_Image (Data.Project) & "|--database|" &
                     To_String (Data.Database) & "|--state|" & State & "|--color|never"));
               Commands.Append
                 (To_Unbounded_String ("plan|show|PLAN-000001|--state|" & State & "|--color|never"));
               Commands.Append
                 (To_Unbounded_String
                    ("apply|PLAN-000001|--dry-run|--database|" & To_String (Data.Database) & "|--state|" & State &
                     "|--color|never"));
               Commands.Append
                 (To_Unbounded_String
                    ("tasks|--project|" & Id_Image (Data.Project) & "|--status|verified|--database|" &
                     To_String (Data.Database) & "|--state|" & State & "|--color|never"));
               Commands.Append
                 (To_Unbounded_String
                    ("status|--project|" & Id_Image (Data.Project) & "|--database|" &
                     To_String (Data.Database) & "|--state|" & State & "|--color|never"));
               Commands.Append (To_Unbounded_String ("recover|--state|" & State & "|--color|never"));
               Commands.Append (To_Unbounded_String ("config|show|--format|json"));
               for Command of Commands loop
                  Result := Improve.CLI.Execute (Args (To_String (Command)));
                  Assert
                    (Result.Exit_Code = 0 and then Length (Result.Output) > 0 and then Length (Result.Errors) = 0,
                     "operational terminal path failed: " & To_String (Command));
               end loop;
               Must_Reject ("--version|projects", "cannot be combined");
               Must_Reject ("help|unknown", "unknown help topic");
               Must_Reject ("plan|show", "requires a plan identity");
               Must_Reject ("status|--all|--project|1", "exactly one");
               Must_Reject ("projects|--dry-run", "not accepted");
               Must_Reject ("tasks|--task=", "requires a value");
               Remove (Data);
            end;
         when Task_Status_Matrix =>
            declare
               Data : constant Fixture := Build_Fixture ("task_status_matrix", Harness_Project => True);
               Plan : Improve.Model.Plan_Revision := Draft_For (Data);
               Only : constant Improve.Model.Task_Specification := Plan.Tasks.First_Element;

               procedure Check
                 (Harness_State : String;
                  Expected      : Improve.Tasks.Operational_Status;
                  Verified      : Boolean := False;
                  Outcome       : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
                  Current_Run   : Natural := 2) is
                  Publications : Improve.Storage.Publication_Vectors.Vector;
                  Evidence     : Improve.Storage.Verification_Vectors.Vector;
                  Views        : Improve.Tasks.View_Vectors.Vector;
               begin
                  if Harness_State /= "" then
                     Publications.Append
                       (Improve.Storage.Publication_Record'
                          (Improve_Task_Id => Only.Id,
                           Harness_Task_Id => To_Unbounded_String ("TASK-TEST-001"),
                           Origin => To_Unbounded_String ("improve:test"),
                           Contract => To_Unbounded_String
                             (Improve.Model.Effective_Task_Contract_Fingerprint (Plan, Only.Id)),
                           State => To_Unbounded_String (Harness_State),
                           Plan_Revision => Plan.Revision));
                  end if;
                  if Verified then
                     Evidence.Append
                       (Improve.Storage.Verification_Record'
                          (Scope => Improve.Storage.Task_Evaluation, Task_Id => Only.Id,
                           Plan_Revision => Plan.Revision,
                           Contract_Fingerprint => To_Unbounded_String
                             (Improve.Verification.Contract_Fingerprint (Only)),
                           Assessment_Id => 2, Outcome => Outcome, Comparable => True,
                           Explanation => To_Unbounded_String ("matrix")));
                  end if;
                  Views := Improve.Tasks.Build
                    (Plan, Publications, Evidence, Current_Assessment => Current_Run);
                  Assert (Views.First_Element.Status = Expected, "unexpected operational task status");
               end Check;
            begin
               declare
                  Joined     : Improve.Model.Plan_Revision := Plan;
                  Unrelated  : Improve.Model.Task_Specification := Only;
                  Evidence   : Improve.Storage.Verification_Vectors.Vector;
                  Ordered    : Improve.Tasks.View_Vectors.Vector;
                  Reordered  : Improve.Tasks.View_Vectors.Vector;
                  Summary    : Improve.Tasks.Finding_Summary;
               begin
                  Unrelated.Id := To_Unbounded_String ("IMP-999999");
                  Unrelated.Finding_Keys.Clear;
                  Joined.Tasks.Clear;
                  Joined.Tasks.Append (Only);
                  Joined.Tasks.Append (Unrelated);
                  Evidence.Append
                    (Improve.Storage.Verification_Record'
                       (Scope => Improve.Storage.Task_Evaluation, Task_Id => Only.Id,
                        Plan_Revision => Joined.Revision,
                        Contract_Fingerprint => To_Unbounded_String
                          (Improve.Verification.Contract_Fingerprint (Only)),
                        Assessment_Id => 2, Outcome => Improve.Model.Verified, Comparable => True,
                        Explanation => To_Unbounded_String ("identity join")));
                  Ordered := Improve.Tasks.Build
                    (Joined, Improve.Storage.Publication_Vectors.Empty_Vector, Evidence,
                     Current_Assessment => 2);
                  Reordered.Append (Ordered.Last_Element);
                  Reordered.Append (Ordered.First_Element);
                  Summary := Improve.Tasks.Findings (Joined, Reordered);
                  Assert
                    (Summary.Resolved = Natural (Only.Finding_Keys.Length),
                     "finding aggregation used task/view position instead of task identity");
               end;
               Plan.Tasks.Clear;
               Plan.Tasks.Append (Only);
               Check ("", Improve.Tasks.Proposed);
               Check ("candidate", Improve.Tasks.Published);
               Check ("accepted", Improve.Tasks.Published);
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
               Assert
                 (Improve.Tasks.Valid_Filter ("unresolved") and then
                  Improve.Tasks.Valid_Filter ("verified") and then
                  not Improve.Tasks.Valid_Filter ("unknown") and then
                  Improve.Tasks.Matches
                    (Improve.Tasks.Build
                       (Plan, Improve.Storage.Publication_Vectors.Empty_Vector,
                        Improve.Storage.Verification_Vectors.Empty_Vector).First_Element,
                     "unresolved"),
                  "task status filter contract is inconsistent");
               Remove (Data);
            end;
         when Real_End_To_End_Workflow =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Work      : constant String := "/tmp/improve_phase9_end_to_end";
               Root      : constant String := Work & "/project";
               Database  : constant String := Work & "/quality.db";
               State     : constant String := Work & "/improve.db";
               Source    : constant String := Root & "/src/e2e_fixture.adb";
               Quality   : Ada_Quality.Storage.Store;
               Project   : Positive;
               First_Run : Positive;
               Next_Run  : Positive;
               Policy    : Ada_Quality.Policy.Quality_Policy := Ada_Quality.Policy.Default;
               Planned   : Improve.CLI.Outcome;
               Applied   : Improve.CLI.Outcome;
               Verified  : Improve.CLI.Outcome;
               Replanned : Improve.CLI.Outcome;
               Repeated  : Improve.CLI.Outcome;
               Plan      : Improve.Model.Plan_Revision;
               New_Plan  : Improve.Model.Plan_Revision;
               Hygiene_Key  : Unbounded_String;
               Hygiene_Task : Unbounded_String;
               Prior_Ids    : Improve.Model.UString_Vectors.Vector;
               Mapping      : Improve.Storage.Publication_Record;
            begin
               Project_Tools.Files.Delete_Tree (Work);
               Ada.Directories.Create_Path (Root & "/src");
               Project_Tools.Files.Write_Text_File
                 (Root & "/alire.toml",
                  "name = ""e2e_fixture""" & ASCII.LF &
                  "description = ""Improve end-to-end fixture""" & ASCII.LF &
                  "version = ""0.1.0""" & ASCII.LF &
                  "licenses = ""MIT""" & ASCII.LF &
                  "authors = [""Improve tests""]" & ASCII.LF &
                  "maintainers = [""Improve tests <tests@example.invalid>""]" & ASCII.LF &
                  "maintainers-logins = [""improve-tests""]" & ASCII.LF &
                  "website = ""https://example.invalid/improve-tests""" & ASCII.LF &
                  "tags = [""test""]" & ASCII.LF &
                  "project-files = [""e2e_fixture.gpr""]" & ASCII.LF &
                  "executables = [""e2e_fixture""]" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/e2e_fixture.gpr",
                  "project E2E_Fixture is" & ASCII.LF &
                  "   for Source_Dirs use (""src"");" & ASCII.LF &
                  "   for Object_Dir use ""obj"";" & ASCII.LF &
                  "   for Exec_Dir use ""bin"";" & ASCII.LF &
                  "   for Main use (""e2e_fixture.adb"");" & ASCII.LF &
                  "end E2E_Fixture;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Source,
                  "procedure E2E_Fixture is" & ASCII.LF &
                  "begin" & ASCII.LF &
                  "   null; " & ASCII.LF &
                  "end E2E_Fixture;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File (Root & "/README.md", "# End-to-end fixture" & ASCII.LF);
               Project_Tools.Files.Write_Text_File (Root & "/LICENSE", "MIT test fixture" & ASCII.LF);
               Ada_Quality.Storage.Open (Quality, Database);
               Project := Ada_Quality.Storage.Add_Project (Quality, Root);
               Ada_Quality.Storage.Close (Quality);
               Policy.Require_Clean_Worktree := False;
               Policy.Process_Timeout_Seconds := 60;
               Policy.Maximum_Output_Bytes := 262_144;
               First_Run := Publish_Real_Assessment (Database, Project, Root, Policy);
               Planned := Improve.CLI.Execute
                 (Args
                    ("plan|--project|" & Id_Image (Project) & "|--run|" & Id_Image (First_Run) &
                     "|--database|" & Database & "|--state|" & State & "|--format|json"));
               Assert (Planned.Exit_Code = 0, "real assessment planning failed: " & To_String (Planned.Errors));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  Improve.Storage.Close (Improve_State);
               end;
               for Finding of Plan.Findings loop
                  if Finding.Indicator = Ada_Quality.Types.SRC_04 then Hygiene_Key := Finding.Fingerprint; exit; end if;
               end loop;
               Assert (Length (Hygiene_Key) > 0, "real assessment did not report the hygiene defect");
               for Spec of Plan.Tasks loop
                  if Spec.Finding_Keys.Contains (Hygiene_Key) then Hygiene_Task := Spec.Id;
                  else Prior_Ids.Append (Spec.Id);
                  end if;
               end loop;
               Assert (Length (Hygiene_Task) > 0, "planner did not create a traceable hygiene task");
               Initialize_Harness (Root);
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args
                    ("apply|PLAN-000001|--task|" & To_String (Hygiene_Task) & "|--database|" & Database &
                     "|--state|" & State & "|--format|json"));
               Assert (Applied.Exit_Code = 0, "native end-to-end publication failed: " & To_String (Applied.Errors));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  for Published of Improve.Storage.Publications (Improve_State, "PLAN-000001") loop
                     if Published.Improve_Task_Id = Hygiene_Task then Mapping := Published; exit; end if;
                  end loop;
                  Improve.Storage.Close (Improve_State);
               end;
               Assert (Length (Mapping.Harness_Task_Id) > 0, "published hygiene task mapping is missing");
               declare
                  Harness  : Stores.Store;
                  Recovery : Stores.Recovery_Report;
                  Change   : Stores.Transaction;
                  Status   : Errors.Error_Info;
               begin
                  Stores.Open (Harness, Root, Recovery, Status);
                  Assert
                    (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 1,
                     "published end-to-end task is not visible in native harness state");
                  Tasks.Move
                    (Harness, Change, To_String (Mapping.Harness_Task_Id), "accepted", "", Status => Status,
                     Actor => "improve-e2e-test");
                  Assert (Errors.Is_Ok (Status), "published end-to-end task could not be accepted");
                  Stores.Commit (Harness, Change, Status);
                  Assert
                    (Errors.Is_Ok (Status) and then
                     Tasks.Next_Work_Of (Harness).Runnable.Contains (To_String (Mapping.Harness_Task_Id)),
                     "accepted end-to-end task is not executable through the ordinary work queue");
                  Stores.Close (Harness);
               end;
               Project_Tools.Files.Write_Text_File
                 (Source,
                  "procedure E2E_Fixture is" & ASCII.LF &
                  "begin" & ASCII.LF &
                  "   null;" & ASCII.LF &
                  "end E2E_Fixture;" & ASCII.LF);
               Next_Run := Publish_Real_Assessment (Database, Project, Root, Policy);
               Verified := Improve.CLI.Execute
                 (Args
                    ("verify|--task|" & To_String (Hygiene_Task) & "|--run|" & Id_Image (Next_Run) &
                     "|--database|" & Database & "|--state|" & State & "|--format|json"));
               Assert
                 (Verified.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Verified.Output), """outcome"":""verified""") > 0,
                  "corrected real finding was not independently verified: " & To_String (Verified.Errors));
               Replanned := Improve.CLI.Execute
                 (Args
                    ("plan|--project|" & Id_Image (Project) & "|--run|" & Id_Image (Next_Run) &
                     "|--database|" & Database & "|--state|" & State & "|--format|json"));
               Repeated := Improve.CLI.Execute
                 (Args
                    ("plan|--project|" & Id_Image (Project) & "|--run|" & Id_Image (Next_Run) &
                     "|--database|" & Database & "|--state|" & State & "|--format|json"));
               Assert
                 (Replanned.Exit_Code = 0 and then Repeated.Exit_Code = 0,
                  "remeasured planning was not repeatable");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  New_Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  Assert
                    (Improve.Storage.List (Improve_State, Project).Length = 1 and then New_Plan.Revision = 2,
                     "remeasured planning did not retain one stable plan with immutable revisions");
                  Improve.Storage.Close (Improve_State);
               end;
               Assert
                 ((for all Finding of New_Plan.Findings => Finding.Indicator /= Ada_Quality.Types.SRC_04),
                  "resolved hygiene evidence remained in the refreshed plan");
               Assert
                 ((for some Id of Prior_Ids =>
                    (for some Spec of New_Plan.Tasks => Spec.Id = Id)),
                  "unrelated remediation task identities were not preserved across assessment revisions");
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args
                    ("apply|PLAN-000001|--database|" & Database & "|--state|" & State & "|--format|json"));
               Repeated := Improve.CLI.Execute
                 (Args
                    ("apply|PLAN-000001|--database|" & Database & "|--state|" & State & "|--format|json"));
               Assert
                 (Applied.Exit_Code = 0 and then Repeated.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Repeated.Output), """recovered"":true") > 0,
                  "repeated native publication was not idempotent");
               declare
                  Harness : Stores.Store;
                  Status  : Errors.Error_Info;
                  Report  : Stores.Recovery_Report;
                  Snapshot : Ada_Quality.Reporting.Session;
               begin
                  Stores.Open (Harness, Root, Report, Status);
                  Assert
                    (Errors.Is_Ok (Status) and then
                     Tasks.List (Harness).Length = New_Plan.Tasks.Length + 1,
                     "repeated publication lost or duplicated native tasks");
                  Stores.Close (Harness);
                  Ada_Quality.Reporting.Open (Snapshot, Database);
                  Assert
                    (Ada_Quality.Reporting.Runs (Snapshot, Project).Length = 2,
                     "real assessment history was not preserved");
                  Ada_Quality.Reporting.Close (Snapshot);
               end;
               Project_Tools.Files.Delete_Tree (Work);
            end;
      when others =>
         raise Program_Error with "non-operational test delegated to operations subunit";
   end case;
end Run_Operations_Test;
