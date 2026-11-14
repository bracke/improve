separate (Improve_Operations_Test_Suite)
procedure Run_Inspection_Test (Item : in out Case_Test) is
begin
   case Item.Id is
         when In_Project_State_Does_Not_Stale_Plan =>
            declare
               Data    : constant Fixture := Build_Fixture ("in_project_state");
               State_Directory : constant String := To_String (Data.Target) & "/state";
               State   : constant String := State_Directory & "/improve.db";
               Planned : Improve.CLI.Outcome;
               Applied : Improve.CLI.Outcome;
            begin
               Ada.Directories.Create_Directory (State_Directory);
               Planned := Prepare_Verification_Plan (Data, State);
               Assert (Planned.Exit_Code = 0, "in-project state fixture planning failed");
               Initialize_Harness (To_String (Data.Target));
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Applied.Exit_Code = 0,
                  "configured in-project state invalidated its own source fingerprint: " &
                  To_String (Applied.Errors));
               Remove (Data);
            end;
         when Tasks_CLI_Golden =>
            declare
               Data     : constant Fixture := Build_Fixture ("tasks_golden");
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
               Data    : constant Fixture := Build_Fixture ("tasks_json");
               State   : constant String := To_String (Data.Directory) & "/improve.db";
               Planned : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Result  : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "tasks JSON fixture plan failed");
               Result := Improve.CLI.Execute
                 (Args ("tasks|--task|IMP-000001|--database|" & To_String (Data.Database) &
                        "|--state|" & State & "|--format|json|--color|always"));
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
               Result := Improve.CLI.Execute
                 (Args ("tasks|--task|IMP-000001|--database|" & To_String (Data.Directory) &
                        "/missing-quality.db|--state|" & State & "|--format|json"));
               Assert
                 (Result.Exit_Code = Improve.CLI.Unavailable_Exit and then Length (Result.Output) = 0,
                  "explicitly unavailable task quality database was silently ignored");
               declare
                  Config_Path : constant String := To_String (Data.Directory) & "/improve.toml";
               begin
                  Project_Tools.Files.Write_Text_File
                    (Config_Path,
                     "schema_version = 2" & ASCII.LF & "[quality]" & ASCII.LF &
                     "database = "".ada-quality.db""" & ASCII.LF);
                  Result := Improve.CLI.Execute
                    (Args ("tasks|--task|IMP-000001|--config|" & Config_Path &
                           "|--state|" & State & "|--format|json"));
                  Assert
                    (Result.Exit_Code = Improve.CLI.Unavailable_Exit and then Length (Result.Output) = 0,
                     "configured default quality database was mistaken for an implicit default");
               end;
               Remove (Data);
            end;
         when Status_Project_And_All =>
            declare
               Data    : constant Fixture := Build_Fixture ("status");
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
               Data       : constant Fixture := Build_Fixture ("status_freshness");
               State      : constant String := To_String (Data.Directory) & "/improve.db";
               Planned    : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Verified   : Positive;
               Latest     : Positive;
               Checked    : Improve.CLI.Outcome;
               JSON_View  : Improve.CLI.Outcome;
               Text_View  : Improve.CLI.Outcome;
               Task_View  : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "status-freshness fixture plan failed");
               Verified := Publish_Followup (Data);
               Checked := Improve.CLI.Execute
                 (Args ("verify|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Verified) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Checked.Exit_Code = 0, "status-freshness verification failed");
               Task_View := Improve.CLI.Execute
                 (Args ("tasks|--task|IMP-000001|--database|" & To_String (Data.Database) &
                        "|--state|" & State & "|--format|json"));
               Assert
                 (Task_View.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Task_View.Output), """verification_current"":true") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Task_View.Output), """verification_run"":" & Id_Image (Verified)) > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Task_View.Output), """verification_freshness"":""current""") > 0,
                  "task-only inspection did not establish current assessment freshness");
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
                    (To_String (JSON_View.Output), """verification_current"":false") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (JSON_View.Output), """verification_freshness"":""historical""") > 0,
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
               First       : constant Fixture := Build_Fixture ("status_all_mixed");
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
      when others =>
         raise Program_Error with "case routed to the wrong operations test group";
   end case;
end Run_Inspection_Test;
