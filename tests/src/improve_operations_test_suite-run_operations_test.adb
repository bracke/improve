separate (Improve_Operations_Test_Suite)
procedure Run_Operations_Test (Item : in out Case_Test) is
begin
   case Item.Id is
         when Configuration_Bounds =>
            declare
               Root : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-config");
               Path : constant String := Root & "/improve.toml";

               procedure Write (Text : String; Version : Positive := 1) is
               begin
                  Project_Tools.Files.Write_Text_File
                    (Path, "schema_version =" & Positive'Image (Version) & ASCII.LF & Text & ASCII.LF);
               end Write;

               procedure Reject (Text, Label : String; Section : String := "") is
                  Rejected : Boolean := False;
               begin
                  Write ((if Section = "" then Text else "[" & Section & "]" & ASCII.LF & Text));
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
                  Write ("[planning]" & ASCII.LF & "minimum_severity = """ & Text & """");
                  Assert (Improve.Config.Load (Path).Minimum_Severity = Expected,
                          "configuration did not preserve severity " & Text);
               end Accept_Severity;
            begin
               Write
                 ("[quality]" & ASCII.LF &
                  "database = ""quality.db""" & ASCII.LF &
                  "selection = ""latest_completed""" & ASCII.LF &
                  "maximum_database_projects = 70" & ASCII.LF &
                  "maximum_database_runs = 700" & ASCII.LF &
                  "maximum_database_findings = 7000" & ASCII.LF &
                  "maximum_database_bytes = 1048576" & ASCII.LF &
                  "maximum_assessment_findings = 77" & ASCII.LF &
                  "maximum_assessment_bytes = 65536" & ASCII.LF &
                  "maximum_normalized_finding_bytes = 32768" & ASCII.LF &
                  "maximum_source_file_bytes = 4096" & ASCII.LF &
                  "maximum_source_total_bytes = 8192" & ASCII.LF &
                  "[planning]" & ASCII.LF &
                  "minimum_severity = ""critical""" & ASCII.LF &
                  "maximum_tasks_per_plan = 7" & ASCII.LF &
                  "maximum_findings_per_task = 6" & ASCII.LF &
                  "allow_investigation_tasks = false" & ASCII.LF &
                  "require_review = false" & ASCII.LF &
                  "agent_max_context_bytes = 4096" & ASCII.LF &
                  "agent_max_file_bytes = 2048" & ASCII.LF &
                  "agent_max_response_bytes = 1024" & ASCII.LF &
                  "agent_timeout_seconds = 2" & ASCII.LF &
                  "[operations]" & ASCII.LF &
                  "maximum_history_items = 12" & ASCII.LF &
                  "maximum_persisted_text_bytes = 16384" & ASCII.LF &
                  "maximum_recovery_operations = 9" & ASCII.LF &
                  "[workflow]" & ASCII.LF &
                  "task_kind = ""remediation""" & ASCII.LF &
                  "publication = ""candidate""" & ASCII.LF &
                  "require_initialized_project = true" & ASCII.LF &
                  "[verification]" & ASCII.LF &
                  "require_fresh_measurement = false" & ASCII.LF &
                  "require_same_policy = false" & ASCII.LF &
                  "require_same_toolchain = true" & ASCII.LF &
                  "require_no_new_critical_findings = false" & ASCII.LF &
                  "[output]" & ASCII.LF &
                  "maximum_output_items = 8" & ASCII.LF &
                  "format = ""json""" & ASCII.LF &
                  "color = ""never""",
                  Version => 2);
               declare Value : constant Improve.Config.Settings := Improve.Config.Load (Path); begin
                  Assert
                    (Value.Minimum_Severity = Improve.Config.Critical and then
                     To_String (Value.Source_Path) = Path and then
                     Value.Maximum_Quality_Projects = 70 and then
                     Value.Maximum_Quality_Runs = 700 and then
                     Value.Maximum_Quality_Findings = 7_000 and then
                     Value.Maximum_Quality_Database_Bytes = 1_048_576 and then
                     Value.Maximum_Assessment_Findings = 77 and then
                     Value.Maximum_Assessment_Bytes = 65_536 and then
                     Value.Maximum_Normalized_Finding_Bytes = 32_768 and then
                     Value.Maximum_Source_File_Bytes = 4_096 and then
                     Value.Maximum_Source_Total_Bytes = 8_192 and then
                     Value.Maximum_Tasks_Per_Plan = 7 and then Value.Maximum_Findings_Per_Task = 6 and then
                     not Value.Allow_Investigation_Tasks and then not Value.Require_Review and then
                     Value.Agent_Max_Context_Bytes = 4_096 and then Value.Maximum_Output_Items = 8 and then
                     Value.Maximum_History_Items = 12 and then
                     Value.Maximum_Persisted_Text_Bytes = 16_384 and then
                     Value.Maximum_Recovery_Operations = 9 and then Value.Format = Improve.Config.JSON_Format and then
                     Value.Color = Improve.Config.Color_Never and then Value.Require_Initialized and then
                     Ada.Strings.Fixed.Index (Improve.Config.Image (Value), "[quality]") > 0 and then
                     Ada.Strings.Fixed.Index (Improve.Config.Image (Value), "[operations]") > 0,
                     "valid nondefault configuration was not preserved");
                  declare
                     Limits : constant Improve.Storage.Read_Limits :=
                       Improve.Operations.Storage_Read_Limits (Value);
                     Quality_Limits : constant Ada_Quality.Reporting.Load_Limits :=
                       Improve.Operations.Quality_Load_Limits (Value);
                  begin
                     Assert
                       (Limits.Maximum_History = 12 and then Limits.Maximum_Text_Bytes = 16_384 and then
                        Limits.Maximum_History /= Value.Maximum_Output_Items and then
                        Quality_Limits.Max_Projects = 70 and then Quality_Limits.Max_Runs = 700 and then
                        Quality_Limits.Max_Findings = 7_000,
                        "storage history and payload limits were coupled to presentation output");
                     Assert
                       (Improve.Config.Evidence_Limits_Of (Value) =
                          (Database_Bytes => 1_048_576, Assessment_Bytes => 65_536,
                           Normalized_Finding_Bytes => 32_768, Source_File_Bytes => 4_096,
                           Source_Total_Bytes => 8_192),
                        "typed evidence limits did not preserve validated configuration");
                  end;
                  Project_Tools.Files.Write_Text_File (Path, Improve.Config.Image (Value));
                  Assert
                    (Improve.Config.Load (Path).Maximum_Quality_Findings = 7_000,
                     "rendered configuration was not parseable");
                  declare
                     Escaped : Improve.Config.Settings := Value;
                  begin
                     Escaped.Quality_Database := To_Unbounded_String
                       ("quality\\quoted""name.db");
                     Escaped.Task_Kind := To_Unbounded_String ("repair\\""quoted");
                     Project_Tools.Files.Write_Text_File (Path, Improve.Config.Image (Escaped));
                     declare Roundtrip : constant Improve.Config.Settings := Improve.Config.Load (Path); begin
                        Assert
                          (Roundtrip.Quality_Database = Escaped.Quality_Database and then
                           Roundtrip.Task_Kind = Escaped.Task_Kind,
                           "rendered configuration did not escape TOML string values");
                     end;
                  end;
                  Write ("[quality]" & ASCII.LF & "database = '\literal\path'");
                  Assert
                    (To_String (Improve.Config.Load (Path).Quality_Database) = "\literal\path",
                     "literal TOML string was not preserved");
                  Write
                    ("[quality]" & ASCII.LF &
                     "database = ""\u00e9\u20ac\U0001f600""");
                  declare
                     Expected : constant String :=
                       Character'Val (16#C3#) & Character'Val (16#A9#) &
                       Character'Val (16#E2#) & Character'Val (16#82#) & Character'Val (16#AC#) &
                       Character'Val (16#F0#) & Character'Val (16#9F#) &
                       Character'Val (16#98#) & Character'Val (16#80#);
                  begin
                     Assert
                       (To_String (Improve.Config.Load (Path).Quality_Database) = Expected,
                        "Unicode TOML escapes were not decoded as UTF-8");
                  end;
               end;
               Project_Tools.Files.Write_Text_File (Path, "schema_version = 3" & ASCII.LF);
               begin
                  declare Value : constant Improve.Config.Settings := Improve.Config.Load (Path);
                     pragma Unreferenced (Value);
                  begin
                     Assert (False, "unsupported configuration schema was accepted");
                  end;
               exception
                  when Improve.Argument_Error => null;
               end;
               Write
                 ("[quality]" & ASCII.LF & "maximum_normalized_finding_bytes = 1024");
               declare Rejected : Boolean := False; begin
                  begin
                     declare Value : constant Improve.Config.Settings := Improve.Config.Load (Path);
                        pragma Unreferenced (Value);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Argument_Error => Rejected := True;
                  end;
                  Assert (Rejected, "schema version 1 accepted version 2 evidence settings");
               end;
               Write ("[quality]" & ASCII.LF & "maximum_assessment_bytes = 1024");
               Assert
                 (Improve.Config.Load (Path).Maximum_Normalized_Finding_Bytes =
                    Improve.Config.Default_Maximum_Normalized_Finding_Bytes,
                  "schema version 1 did not apply defaults for version 2 settings");
               Accept_Severity ("info", Improve.Config.Info);
               Accept_Severity ("medium", Improve.Config.Medium);
               Accept_Severity ("high", Improve.Config.High);
               Reject ("selection = ""newest""", "selection", "quality");
               Reject ("database = """"", "empty database", "quality");
               Reject ("database = bare", "unquoted string", "quality");
               Reject ("database = ""bad\q""", "unknown string escape", "quality");
               Reject ("database = ""bad\npath""", "escaped database control", "quality");
               Reject ("task_kind = ""repair\u0000kind""", "escaped task-kind control", "workflow");
               Reject
                 ("database = ""bad" & ASCII.BS & "path""",
                  "unescaped string control", "quality");
               Reject ("database = ""\u12""", "short Unicode escape", "quality");
               Reject ("database = ""\u00xz""", "invalid Unicode escape", "quality");
               Reject ("database = ""\ud800""", "surrogate Unicode escape", "quality");
               Reject ("database = ""\U00110000""", "out-of-range Unicode escape", "quality");
               Reject ("database = ""value"" trailing", "trailing string data", "quality");
               Reject ("maximum_database_projects = 100001", "quality project limit", "quality");
               Reject ("maximum_database_runs = 10000001", "quality run limit", "quality");
               Reject ("maximum_database_findings = 10000001", "quality finding load limit", "quality");
               Reject ("maximum_database_bytes = 2000000001", "quality database byte limit", "quality");
               Reject ("maximum_assessment_findings = 1000001", "assessment finding limit", "quality");
               Reject ("maximum_assessment_bytes = 268435457", "assessment byte limit", "quality");
               Reject
                 ("maximum_normalized_finding_bytes = 268435457",
                  "normalized finding byte limit", "quality");
               Reject
                 ("maximum_source_file_bytes = 3" & ASCII.LF & "maximum_source_total_bytes = 2",
                  "source file and total relationship", "quality");
               Reject ("minimum_severity = ""urgent""", "severity", "planning");
               Reject ("task_kind = """"", "task kind", "workflow");
               Reject ("publication = ""accepted""", "publication mode", "workflow");
               Reject ("require_initialized_project = false", "initialized project policy", "workflow");
               Reject ("format = ""yaml""", "output format", "output");
               Reject ("color = ""sometimes""", "color policy", "output");
               Reject ("maximum_tasks_per_plan = 0", "zero task limit", "planning");
               Reject ("maximum_tasks_per_plan = 10001", "task limit", "planning");
               Reject ("maximum_findings_per_task = 10001", "finding limit", "planning");
               Reject ("agent_max_context_bytes = 1000", "small agent context", "planning");
               Reject
                 ("agent_max_context_bytes = 1024" & ASCII.LF & "agent_max_file_bytes = 2048",
                  "agent file limit", "planning");
               Reject ("agent_max_response_bytes = 1048577", "agent response limit", "planning");
               Reject ("agent_timeout_seconds = 3601", "agent timeout", "planning");
               Reject ("maximum_output_items = 100001", "output item limit", "output");
               Reject ("maximum_history_items = 1000001", "history item limit", "operations");
               Reject ("maximum_persisted_text_bytes = 16777217", "persisted text limit", "operations");
               Reject ("maximum_recovery_operations = 10001", "recovery limit", "operations");
               Reject ("require_review = maybe", "boolean", "planning");
               Reject ("database = ""wrong.db""", "misplaced setting", "output");
               Reject
                 ("[quality]" & ASCII.LF & "database = ""a.db""" & ASCII.LF & "database = ""b.db""",
                  "duplicate setting");
               Reject
                 ("[quality]" & ASCII.LF & "database = ""a.db""" & ASCII.LF &
                  "[quality]" & ASCII.LF & "selection = ""latest_completed""",
                  "duplicate section");
               Reject ("[unknown]" & ASCII.LF & "value = 1", "unknown section");
               declare Rejected : Boolean := False; begin
                  Project_Tools.Files.Write_Text_File (Path, [1 .. 1_048_577 => '#']);
                  begin
                     declare Value : constant Improve.Config.Settings := Improve.Config.Load (Path);
                        pragma Unreferenced (Value);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Argument_Error => Rejected := True;
                  end;
                  Assert (Rejected, "oversized configuration was accepted");
               end;
               Project_Tools.Files.Delete_File_If_Present (Path);
               Project_Tools.Files.Delete_Tree (Root);
            end;
         when Operational_Terminal_Paths =>
            declare
               Data    : constant Fixture := Build_Fixture ("terminal_paths");
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
         when Real_End_To_End_Workflow =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Work      : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-e2e");
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
                  if Finding.Indicator = Ada_Quality.Types.SRC_04 then
                     Hygiene_Key := To_Unbounded_String (Improve.Model.Finding_Key (Finding));
                     exit;
                  end if;
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
                    (Improve.Storage.List (Improve_State, New_Plan.Project).Length = 1 and then
                     New_Plan.Revision = 2,
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
         raise Program_Error with "case routed to the wrong operations test group";
   end case;
end Run_Operations_Test;
