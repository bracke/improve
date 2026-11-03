with Ada.Directories;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Exceptions;
with Ada_Quality.Checks;
with Ada_Quality.Policy;
with Ada_Quality.Reporting;
with Ada_Quality.Storage;
with Ada_Quality.Types;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve;
with Improve.CLI;
with Improve.Config;
with Improve.Dependencies;
with Improve.Findings;
with Improve.Model;
with Improve.Planner;
with Improve.Presentation;
with Improve.Refinement;
with Improve.Recovery;
with Improve.Rules;
with Improve.Source;
with Improve.Storage;
with Improve.Tasks;
with Improve.Text;
with Improve.Verification;
with Improve.Workflow;
with Model_Runner.Errors;
with Model_Runner.Framework.Configurations;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;
with Model_Runner.Framework.Templates;
with Project_Tools.Files;

package body Improve_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Improve.CLI.Command_Kind;
   use type Improve.CLI.Plan_Operation;
   use type Improve.Config.Color_Mode;
   use type Improve.Config.Output_Format;
   use type Improve.Config.Severity_Level;
   use type Improve.Model.Candidate_Kind;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Model.Task_Vectors.Vector;
   use type Improve.Refinement.Refinement_Status;
   use type Improve.Refinement.Source_State;
   use type Improve.Storage.Verification_Scope;
   use type Improve.Tasks.Operational_Status;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Types.Indicator_Id;

   type Test_Id is
     (Parse_Plan, Reject_Duplicate, Reject_Conflict, Reject_Missing_Project, Reject_Command_Option,
      JSON_Disables_Color, Help_Smoke, Version_Smoke, Config_Smoke, Invalid_Smoke, Catalog, Digest,
      Project_Discovery, Latest_Completed, Explicit_Incomplete_Rejected, Normalize_Findings,
      Unknown_Project_Rejected, Safe_Path_Validation, Projects_CLI, Findings_CLI,
      Complete_Strategy_Registry, Deterministic_Planner, Planner_Grouping_And_Splitting,
      Dependency_Cycle_Rejected, Plan_Dry_Run_CLI, Persistent_Plan_Roundtrip,
      Repeated_Plan_Idempotent, Persisted_Dependency_Translation, Read_Only_Does_Not_Initialize,
      Plan_Approval_Required, Current_Source_Staleness_Detected, Historical_Task_Lookup,
      Measurement_Source_Mismatch_Blocks_Plan, Quality_Database_Identity_Rejected,
      Quality_Database_Histories_Isolated,
      Native_Publication_And_Recovery, Selective_Publication_Resolves_Dependency, Refresh_Reconciles_State,
      Verification_Resolved, Verification_Still_Failing,
      Verification_Task_Scope_Not_Project, Verification_Severity_Drop_Outstanding,
      Verification_Partially_Resolved, Verification_Missing_Evidence, Verification_Regressed,
      Unrelated_Critical_Project_Regression, Out_Of_Order_Verification_Not_Regression,
      Verification_Policy_Changed, Verification_Incomplete_Rejected, Verification_Revisions_Coexist,
      Agent_Context_Bounded,
      Agent_Valid_Refinement, Agent_Malformed_Fallback, Agent_Missing_File_Rejected,
      Agent_Invented_Evidence_Rejected, Agent_Invalid_Category_Rejected, Agent_Cycle_Rejected,
      Agent_Timeout_Fallback, Agent_Unavailable_Fallback, Agent_Weakening_Rejected,
      Tasks_CLI_Golden, Tasks_JSON_Filter, Status_Project_And_All, Status_Verification_Freshness,
      Status_All_Mixed_Freshness, Interrupted_Publication_Recovery,
      Recovery_Rejects_Stale_Uncommitted,
      Published_Task_Reused_Across_Revisions, Recovery_Uses_Exact_Revision,
      Recovery_Limit_Enforced, Recover_Missing_State, Configuration_Bounds,
      Operational_Terminal_Paths, Task_Status_Matrix, Real_End_To_End_Workflow);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding function Name (Item : Case_Test) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Case_Test);

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_" & Test_Id'Image (Item.Id)));

   function Args (Text : String) return Improve.CLI.String_Vectors.Vector is
      Result : Improve.CLI.String_Vectors.Vector;
      Start  : Positive := Text'First;
   begin
      if Text = "" then return Result; end if;
      for Index in Text'Range loop
         if Text (Index) = '|' then
            Result.Append (Text (Start .. Index - 1)); Start := Index + 1;
         end if;
      end loop;
      Result.Append (Text (Start .. Text'Last));
      return Result;
   end Args;

   function Id_Image (Value : Positive) return String is
     (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

   procedure Must_Reject (Text, Expected : String) is
      Rejected : Boolean := False;
   begin
      begin
         declare Item : constant Improve.CLI.Invocation := Improve.CLI.Parse (Args (Text));
            pragma Unreferenced (Item);
         begin null; end;
      exception
         when Error : Improve.Argument_Error =>
            Rejected := Ada.Strings.Fixed.Index (Ada.Exceptions.Exception_Message (Error), Expected) > 0;
      end;
      Assert (Rejected, "expected rejection containing '" & Expected & "'");
   end Must_Reject;

   type Fixture is record
      Directory : Unbounded_String;
      Database  : Unbounded_String;
      Project   : Positive;
      Run       : Positive;
      Interrupted : Positive;
      Target      : Unbounded_String;
   end record;

   function Build_Fixture
     (Label              : String;
      Harness_Project    : Boolean := False;
      Multiple_Structure : Boolean := False) return Fixture is
      use Ada_Quality.Types;
      Directory : constant String := "/tmp/improve_phase2_" & Label;
      DB_Path   : constant String := Directory & "/quality.db";
      Store     : Ada_Quality.Storage.Store;
      Project   : Positive;
      Run       : Positive;
      Later     : Positive;
      Value     : Assessment;
      Target    : constant String :=
        (if Harness_Project then Directory & "/project" else Ada.Directories.Full_Name (".."));
   begin
      Project_Tools.Files.Delete_Tree (Directory);
      Ada.Directories.Create_Directory (Directory);
      if Harness_Project then
         Ada.Directories.Create_Directory (Target);
         Project_Tools.Files.Write_Text_File
           (Target & "/alire.toml",
            "name = ""improve_fixture""" & Character'Val (10) &
            "description = ""Improve integration fixture""" & Character'Val (10) &
            "version = ""0.1.0-dev""" & Character'Val (10) &
            "authors = [""Improve tests""]" & Character'Val (10) &
            "maintainers = [""Improve tests <tests@example.invalid>""]" & Character'Val (10) &
            "maintainers-logins = [""improve-tests""]" & Character'Val (10) &
            "licenses = ""MIT""" & Character'Val (10) &
            "tags = [""test""]" & Character'Val (10));
      end if;
      Ada_Quality.Storage.Open (Store, DB_Path);
      Project := Ada_Quality.Storage.Add_Project (Store, Target);
      declare Source : constant String := Ada_Quality.Checks.Source_Fingerprint (Target); begin
         Run := Ada_Quality.Storage.Start_Assessment (Store, Project, Source, "policy-a");
         Value.Source_Fingerprint := To_Unbounded_String (Source);
      end;
      Value.Id := Run;
      Value.Project_Id := Project;
      Value.Project_Path := To_Unbounded_String (Target);
      Value.Policy_Fingerprint := To_Unbounded_String ("policy-a");
      Value.Toolchain_Fingerprint := To_Unbounded_String ("gnat-15.2.1");
      Value.Status := Assessment_Completed;
      for Indicator in Indicator_Id loop
         Value.Results.Append
           (Indicator_Result'
              (Indicator  => Indicator,
               Execution  => Succeeded,
               Compliance => (if Indicator in STR_01 | TST_03 then Violation else Pass),
               Applicable => True,
               Summary     => To_Unbounded_String (if Indicator in STR_01 | TST_03 then "violation" else "pass"),
               Evidence    => To_Unbounded_String ("fixture evidence for " & Image (Indicator)),
               Measurement =>
                 (if Indicator = TST_03 then (Kind => Decimal_Value, Basis_Points => 8_200)
                  else (Kind => Boolean_Value, Boolean_Data => Indicator not in STR_01 | TST_03)),
               Findings    => <>));
      end loop;
      declare
         Structure : Indicator_Result := Value.Results (Value.Results.First_Index);
         Toolchain : Indicator_Result := Value.Results (Value.Results.First_Index + 8);
         Finding   : constant Ada_Quality.Types.Finding :=
           (Indicator    => STR_01,
            Rule         => To_Unbounded_String ("manifest.invalid"),
            Level        => High,
            Message      => To_Unbounded_String ("manifest is invalid"),
            Relative_Path => To_Unbounded_String ("alire.toml"),
            Line         => 1,
            Fingerprint  => To_Unbounded_String ("fixture-manifest"));
      begin
         Structure.Findings.Append (Finding);
         Structure.Findings.Append (Finding);
         if Multiple_Structure then
            Structure.Findings.Append
              (Ada_Quality.Types.Finding'
                 (Indicator     => STR_01,
                  Rule          => To_Unbounded_String ("manifest.invalid"),
                  Level         => High,
                  Message       => To_Unbounded_String ("manifest has a second invalid field"),
                  Relative_Path => To_Unbounded_String ("alire.toml"),
                  Line          => 2,
                  Fingerprint   => To_Unbounded_String ("fixture-manifest-second")));
         end if;
         Value.Results.Replace_Element (Value.Results.First_Index, Structure);
         Toolchain.Execution := Blocked;
         Toolchain.Compliance := Unknown;
         Toolchain.Summary := To_Unbounded_String ("toolchain unavailable");
         Toolchain.Measurement :=
           (Kind => Unavailable_Value, Reason => To_Unbounded_String ("toolchain probe unavailable"));
         Value.Results.Replace_Element (Value.Results.First_Index + 8, Toolchain);
      end;
      Run := Ada_Quality.Storage.Publish (Store, Value);
      Later := Ada_Quality.Storage.Start_Assessment (Store, Project, "source-b", "policy-a");
      Ada_Quality.Storage.Interrupt_Assessment (Store, Later, "fixture interruption");
      Ada_Quality.Storage.Close (Store);
      return
        (To_Unbounded_String (Directory), To_Unbounded_String (DB_Path), Project, Run, Later,
         To_Unbounded_String (Target));
   end Build_Fixture;

   function Add_Fixture_Project (Data : Fixture; Label : String) return Fixture is
      use Ada_Quality.Types;
      Target  : constant String := To_String (Data.Directory) & "/" & Label;
      Store   : Ada_Quality.Storage.Store;
      Project : Positive;
      Run     : Positive;
      Later   : Positive;
      Value   : Assessment;
   begin
      Ada.Directories.Create_Directory (Target);
      Project_Tools.Files.Write_Text_File
        (Target & "/alire.toml",
         "name = ""improve_fixture_" & Label & """" & ASCII.LF &
         "version = ""0.1.0-dev""" & ASCII.LF &
         "licenses = ""MIT""" & ASCII.LF);
      Ada_Quality.Storage.Open (Store, To_String (Data.Database));
      Project := Ada_Quality.Storage.Add_Project (Store, Target);
      declare Source : constant String := Ada_Quality.Checks.Source_Fingerprint (Target); begin
         Run := Ada_Quality.Storage.Start_Assessment (Store, Project, Source, "policy-a");
         Value.Source_Fingerprint := To_Unbounded_String (Source);
      end;
      Value.Id := Run;
      Value.Project_Id := Project;
      Value.Project_Path := To_Unbounded_String (Target);
      Value.Policy_Fingerprint := To_Unbounded_String ("policy-a");
      Value.Toolchain_Fingerprint := To_Unbounded_String ("gnat-15.2.1");
      Value.Status := Assessment_Completed;
      for Indicator in Indicator_Id loop
         Value.Results.Append
           (Indicator_Result'
              (Indicator  => Indicator,
               Execution  => Succeeded,
               Compliance => (if Indicator = STR_01 then Violation else Pass),
               Applicable => True,
               Summary     => To_Unbounded_String (if Indicator = STR_01 then "violation" else "pass"),
               Evidence    => To_Unbounded_String ("fixture evidence for " & Image (Indicator)),
               Measurement => (Kind => Boolean_Value, Boolean_Data => Indicator /= STR_01),
               Findings    => <>));
      end loop;
      declare Structure : Indicator_Result := Value.Results.First_Element; begin
         Structure.Findings.Append
           (Finding'
              (Indicator     => STR_01,
               Rule          => To_Unbounded_String ("manifest.invalid"),
               Level         => High,
               Message       => To_Unbounded_String ("manifest is invalid"),
               Relative_Path => To_Unbounded_String ("alire.toml"),
               Line          => 1,
               Fingerprint   => To_Unbounded_String ("fixture-" & Label & "-manifest")));
         Value.Results.Replace_Element (Value.Results.First_Index, Structure);
      end;
      Run := Ada_Quality.Storage.Publish (Store, Value);
      Later := Ada_Quality.Storage.Start_Assessment (Store, Project, "interrupted-source", "policy-a");
      Ada_Quality.Storage.Interrupt_Assessment (Store, Later, "fixture interruption");
      Ada_Quality.Storage.Close (Store);
      return
        (Directory => Data.Directory,
         Database => Data.Database,
         Project => Project,
         Run => Run,
         Interrupted => Later,
         Target => To_Unbounded_String (Target));
   end Add_Fixture_Project;

   procedure Initialize_Harness (Directory : String) is
      package Config renames Model_Runner.Framework.Configurations;
      package Errors renames Model_Runner.Errors;
      package Stores renames Model_Runner.Framework.Stores;
      package Templates renames Model_Runner.Framework.Templates;
      Template : Templates.Template;
      Registry : Templates.Registry;
      Composed : Templates.Composition;
      Given    : Config.Value_Maps.Map;
      Planned  : Config.Plan;
      Done     : Config.Outcome;
      Store    : Stores.Store;
      Status   : Errors.Error_Info;
   begin
      Templates.Parse
        ("template = improve-tests" & Character'Val (10) &
         "name = Improve tests" & Character'Val (10) &
         "description = Native Improve task publication fixture" & Character'Val (10) &
         "version = 1" & Character'Val (10) &
         "task_kind remediation = acceptance, notes?" & Character'Val (10),
         "improve-tests", Template, Status);
      Assert (Errors.Is_Ok (Status), "harness template parsing failed");
      Templates.Add (Registry, Template);
      Templates.Compose (Registry, "improve-tests", Composed, Status);
      Assert (Errors.Is_Ok (Status), "harness template composition failed");
      Config.Prepare (Composed, Directory, Given, Planned, Status);
      Assert (Errors.Is_Ok (Status), "harness fixture preparation failed");
      Config.Initialize (Store, Directory, Planned, Done, Status);
      Assert (Errors.Is_Ok (Status), "harness fixture initialization failed");
      Stores.Close (Store);
   end Initialize_Harness;

   procedure Remove (Item : Fixture) is
   begin
      Project_Tools.Files.Delete_Tree (To_String (Item.Directory));
   end Remove;

   function Publish_Real_Assessment
     (Database : String;
      Project  : Positive;
      Root     : String;
      Policy   : Ada_Quality.Policy.Quality_Policy) return Positive is
      Store : Ada_Quality.Storage.Store;
      Run   : Natural := 0;
   begin
      Ada_Quality.Storage.Open (Store, Database);
      Run := Ada_Quality.Storage.Start_Assessment
        (Store, Project, Ada_Quality.Checks.Source_Fingerprint (Root), Ada_Quality.Policy.Fingerprint (Policy));
      declare
         Value : Ada_Quality.Types.Assessment := Ada_Quality.Checks.Assess (Project, Root, Policy);
      begin
         Value.Id := Run;
         if Ada_Quality.Storage.Publish (Store, Value) /= Run then
            raise Program_Error with "real assessment publication changed its identity";
         end if;
      end;
      Ada_Quality.Storage.Close (Store);
      return Positive (Run);
   exception
      when others =>
         if Ada_Quality.Storage.Is_Open (Store) then
            if Run > 0 then
               Ada_Quality.Storage.Interrupt_Assessment
                 (Store, Positive (Run), "end-to-end assessment aborted");
            end if;
            Ada_Quality.Storage.Close (Store);
         end if;
         raise;
   end Publish_Real_Assessment;

   type Followup_State is (All_Pass, Structure_Failing, Structure_Unmeasurable);

   function Publish_Followup
     (Data            : Fixture;
      Structure_State : Followup_State := All_Pass;
      Policy           : String := "policy-a";
      Source           : String := "";
      Toolchain        : String := "gnat-15.2.1";
      Structure_Severity : Ada_Quality.Types.Severity := Ada_Quality.Types.High;
      New_Critical     : Boolean := False) return Positive is
      use Ada_Quality.Types;
      Store : Ada_Quality.Storage.Store;
      Run   : Positive;
      Value : Assessment;
      Effective_Source : constant String :=
        (if Source = "" then Ada_Quality.Checks.Source_Fingerprint (To_String (Data.Target)) else Source);
   begin
      Ada_Quality.Storage.Open (Store, To_String (Data.Database));
      Run := Ada_Quality.Storage.Start_Assessment (Store, Data.Project, Effective_Source, Policy);
      Value.Id := Run;
      Value.Project_Id := Data.Project;
      Value.Project_Path := Data.Target;
      Value.Source_Fingerprint := To_Unbounded_String (Effective_Source);
      Value.Policy_Fingerprint := To_Unbounded_String (Policy);
      Value.Toolchain_Fingerprint := To_Unbounded_String (Toolchain);
      Value.Status := Assessment_Completed;
      for Indicator in Indicator_Id loop
         Value.Results.Append
           (Indicator_Result'
              (Indicator  => Indicator,
               Execution  =>
                 (if Structure_State = Structure_Unmeasurable and then Indicator = STR_01 then Blocked
                  else Succeeded),
               Compliance =>
                 (if Structure_State = Structure_Failing and then Indicator = STR_01 then Violation
                  elsif Structure_State = Structure_Unmeasurable and then Indicator = STR_01 then Unknown
                  else Pass),
               Applicable => True,
               Summary     => To_Unbounded_String
                 (if Structure_State = Structure_Failing and then Indicator = STR_01 then "violation"
                  elsif Structure_State = Structure_Unmeasurable and then Indicator = STR_01
                  then "measurement unavailable"
                  else "pass"),
               Evidence    => To_Unbounded_String ("follow-up evidence for " & Image (Indicator)),
               Measurement =>
                 (if Structure_State = Structure_Unmeasurable and then Indicator = STR_01
                  then (Kind => Unavailable_Value, Reason => To_Unbounded_String ("fixture evidence unavailable"))
                  else (Kind => Boolean_Value,
                        Boolean_Data => not (Structure_State = Structure_Failing and then Indicator = STR_01))),
               Findings => <>));
      end loop;
      if Structure_State = Structure_Failing then
         declare Structure : Indicator_Result := Value.Results.First_Element; begin
            Structure.Findings.Append
              (Finding'
                 (Indicator     => STR_01,
                Rule          => To_Unbounded_String ("manifest.invalid"),
                Level         => Structure_Severity,
                Message       => To_Unbounded_String ("manifest is invalid"),
                Relative_Path => To_Unbounded_String ("alire.toml"),
                Line          => 1,
                Fingerprint   => To_Unbounded_String ("fixture-manifest")));
            Value.Results.Replace_Element (Value.Results.First_Index, Structure);
         end;
      end if;
      if New_Critical then
         declare
            Index    : constant Positive := Value.Results.First_Index + Indicator_Id'Pos (SEC_01);
            Security : Indicator_Result := Value.Results (Index);
         begin
            Security.Compliance := Violation;
            Security.Summary := To_Unbounded_String ("new critical security violation");
            Security.Measurement := (Kind => Boolean_Value, Boolean_Data => False);
            Security.Findings.Append
              (Finding'
                 (Indicator     => SEC_01,
                  Rule          => To_Unbounded_String ("security.new-critical"),
                  Level         => Critical,
                  Message       => To_Unbounded_String ("unrelated critical finding"),
                  Relative_Path => To_Unbounded_String ("src/new_issue.adb"),
                  Line          => 1,
                  Fingerprint   => To_Unbounded_String ("fixture-new-critical")));
            Value.Results.Replace_Element (Index, Security);
         end;
      end if;
      Run := Ada_Quality.Storage.Publish (Store, Value);
      Ada_Quality.Storage.Close (Store);
      return Run;
   end Publish_Followup;

   function Prepare_Verification_Plan (Data : Fixture; State : String) return Improve.CLI.Outcome is
     (Improve.CLI.Execute
        (Args ("plan|--database|" & To_String (Data.Database) & "|--state|" & State & "|--project|" &
               Id_Image (Data.Project) & "|--format|json")));

   procedure Approve_Latest (State : String) is
      Result : constant Improve.CLI.Outcome :=
        Improve.CLI.Execute (Args ("plan|approve|PLAN-000001|--state|" & State & "|--format|json"));
   begin
      Assert
        (Result.Exit_Code = 0 and then
         Ada.Strings.Fixed.Index (To_String (Result.Output), """approved"":true") > 0,
         "plan approval failed: " & To_String (Result.Errors));
   end Approve_Latest;

   function Draft_For (Data : Fixture) return Improve.Model.Plan_Revision is
      Quality  : Improve.Source.Repository;
      Settings : constant Improve.Config.Settings := Improve.Config.Defaults;
   begin
      Improve.Source.Open (Quality, To_String (Data.Database));
      declare
         Project  : constant Improve.Model.Project_Reference :=
           Improve.Source.Resolve_Project (Quality, Id_Image (Data.Project));
         Selected : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Quality, Project);
         Findings : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Selected);
         Result   : constant Improve.Model.Plan_Revision := Improve.Planner.Generate (Selected, Findings, Settings);
      begin
         Improve.Source.Close (Quality);
         return Result;
      end;
   end Draft_For;

   type Fake_Mode is
     (Valid_Agent, Malformed_Agent, Missing_File_Agent, Invented_Evidence_Agent, Invalid_Category_Agent,
      Cyclic_Agent, Slow_Agent, Unavailable_Agent, Weakening_Agent);

   type Fake_Adapter is new Improve.Refinement.Adapter with record
      Mode           : Fake_Mode := Valid_Agent;
      Draft          : Improve.Model.Plan_Revision;
      Expected_Limit : Positive := 131_072;
      Saw_Bounded    : Boolean := False;
      Saw_Source     : Boolean := False;
   end record;

   overriding function Name (Self : Fake_Adapter) return String;

   overriding procedure Request
     (Self            : in out Fake_Adapter;
      Context         : Improve.Refinement.Planning_Context;
      Timeout_Seconds : Positive;
      Response        : out Improve.Refinement.Agent_Response);

   overriding function Name (Self : Fake_Adapter) return String is
   begin
      pragma Unreferenced (Self);
      return "aunit-structured-adapter-v1";
   end Name;

   overriding procedure Request
     (Self            : in out Fake_Adapter;
      Context         : Improve.Refinement.Planning_Context;
      Timeout_Seconds : Positive;
      Response        : out Improve.Refinement.Agent_Response) is
      pragma Unreferenced (Timeout_Seconds);
   begin
      Self.Saw_Bounded := Context.Byte_Count <= Self.Expected_Limit;
      for Source of Context.Sources loop
         if Source.State = Improve.Refinement.Source_Available and then Length (Source.Content) > 0 then
            Self.Saw_Source := True;
         end if;
      end loop;
      case Self.Mode is
         when Malformed_Agent =>
            Response.Status := Improve.Refinement.Malformed_Response;
            Response.Diagnostic := To_Unbounded_String ("fixture malformed response");
            return;
         when Slow_Agent => delay 2.0;
         when Unavailable_Agent =>
            Response.Status := Improve.Refinement.Agent_Unavailable;
            Response.Diagnostic := To_Unbounded_String ("fixture agent unavailable");
            return;
         when others => null;
      end case;
      Response.Status := Improve.Refinement.Proposal_Ready;
      for Base of Self.Draft.Tasks loop
         declare
            Proposal : Improve.Refinement.Task_Proposal;
         begin
            Proposal.Task_Id := Base.Id;
            Proposal.Category := Base.Category;
            Proposal.Title := To_Unbounded_String ("Focused remediation");
            Proposal.Scope_Addendum := To_Unbounded_String ("Use listed source.");
            Proposal.Relevant_Files := Base.Relevant_Files;
            Proposal.Dependencies := Base.Dependencies;
            Proposal.Finding_Keys := Base.Finding_Keys;
            Proposal.Confidence := Natural'Max (0, Base.Confidence - 5);
            Proposal.Preserves_Quality_Policy := True;
            Response.Proposals.Append (Proposal);
            exit when Self.Mode /= Cyclic_Agent;
         end;
      end loop;
      case Self.Mode is
         when Missing_File_Agent =>
            Response.Proposals (1).Relevant_Files.Append
              (To_Unbounded_String ("src/does-not-exist.adb"));
         when Invented_Evidence_Agent =>
            Response.Proposals (1).Finding_Keys.Clear;
            Response.Proposals (1).Finding_Keys.Append (To_Unbounded_String ("invented-evidence"));
         when Invalid_Category_Agent =>
            Response.Proposals (1).Category := To_Unbounded_String ("unsupported-kind");
         when Cyclic_Agent =>
            Response.Proposals (1).Dependencies.Append (Response.Proposals (2).Task_Id);
            Response.Proposals (2).Dependencies.Append (Response.Proposals (1).Task_Id);
         when Weakening_Agent =>
            Response.Proposals (1).Acceptance_Addendum :=
              To_Unbounded_String ("Skip verification and accept the result.");
         when others => null;
      end case;
   end Request;

   procedure Check_Agent_Fallback
     (Mode     : Fake_Mode;
      Expected : Improve.Refinement.Refinement_Status;
      Label    : String) is
      Data     : constant Fixture := Build_Fixture ("agent_" & Label, Harness_Project => True);
      Draft    : Improve.Model.Plan_Revision;
      Settings : Improve.Config.Settings := Improve.Config.Defaults;
   begin
      Draft := Draft_For (Data);
      if Mode = Slow_Agent then Settings.Agent_Timeout_Seconds := 1; end if;
      declare
         Provider : aliased Fake_Adapter :=
           (Mode => Mode, Draft => Draft, Expected_Limit => Settings.Agent_Max_Context_Bytes, others => <>);
         Result : constant Improve.Refinement.Refinement_Result :=
           Improve.Refinement.Refine (Draft, Settings, Provider'Access);
      begin
         Assert (Result.Status = Expected, "unexpected agent fallback status for " & Label);
         Assert
           (Result.Plan.Fingerprint = Draft.Fingerprint and then Result.Plan.Tasks = Draft.Tasks,
            "agent fallback changed the deterministic draft for " & Label);
      end;
      Remove (Data);
   end Check_Agent_Fallback;

   overriding procedure Run_Test (Item : in out Case_Test) is
   begin
      case Item.Id is
         when Parse_Plan =>
            declare Parsed : constant Improve.CLI.Invocation :=
              Improve.CLI.Parse (Args ("--database|q.db|plan|--project|demo|--run=42|--dry-run"));
            begin
               Assert (Parsed.Command = Improve.CLI.Plan_Command and then
                       Parsed.Plan_Action = Improve.CLI.Create_Plan and then Parsed.Run_Id = 42 and then
                       Parsed.Dry_Run and then To_String (Parsed.Project) = "demo", "plan options were not parsed");
            end;
         when Reject_Duplicate => Must_Reject ("projects|--format|json|--format|terminal", "more than once");
         when Reject_Conflict => Must_Reject ("projects|--verbose|--quiet", "mutually exclusive");
         when Reject_Missing_Project => Must_Reject ("findings", "requires --project");
         when Reject_Command_Option => Must_Reject ("projects|--run|1", "not accepted");
         when JSON_Disables_Color =>
            declare Parsed : constant Improve.CLI.Invocation :=
              Improve.CLI.Parse (Args ("projects|--format|json|--color|always"));
            begin Assert (Parsed.Color = Improve.Config.Color_Never, "JSON did not force color off"); end;
         when Help_Smoke =>
            declare Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("help"));
            begin
               Assert
                 (Result.Exit_Code = 0 and then
                    Ada.Strings.Fixed.Index (To_String (Result.Output), "Usage:") > 0,
                  "help did not succeed");
            end;
         when Version_Smoke =>
            declare Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("version|--format|json"));
            begin
               Assert
                 (Result.Exit_Code = 0 and then
                    Ada.Strings.Fixed.Index (To_String (Result.Output), """schema_version"":1") > 0,
                  "JSON version output is not versioned");
            end;
         when Config_Smoke =>
            declare Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("config|validate"));
            begin Assert (Result.Exit_Code = 0, "configuration validation failed: " & To_String (Result.Errors)); end;
         when Invalid_Smoke =>
            declare Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("unknown"));
            begin Assert (Result.Exit_Code = 2 and then Length (Result.Output) = 0 and then Length (Result.Errors) > 0,
                          "invalid command did not observe the output contract"); end;
         when Catalog =>
            Assert (Improve.Text.Catalog_Is_Valid, "message catalog is invalid");
            declare
               Value : constant Improve.Text.Argument := Improve.Text.Arg ("name", "value");
               Rejected : Boolean := False;
            begin
               Assert (To_String (Value.Name) = "name" and then To_String (Value.Value) = "value",
                       "message argument construction failed");
               begin
                  declare Text : constant String := Improve.Text.Message ("missing.key"); begin
                     Assert (Text = "", "missing catalog message unexpectedly rendered");
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "missing catalog key was accepted");
               Improve.Presentation.Configure (Improve.Config.Terminal_Format, Improve.Config.Color_Always);
               Assert (Improve.Presentation.Header ("Improve") /= "", "styled header was empty");
               Improve.Presentation.Configure (Improve.Config.Terminal_Format, Improve.Config.Color_Never);
            end;
         when Digest => Assert (Improve.Stable_Digest ("improve") = Improve.Stable_Digest ("improve") and then
                                Improve.Stable_Digest ("improve") /= Improve.Stable_Digest ("Improve"),
                                "stable digest is not deterministic or discriminating");
         when Project_Discovery =>
            declare
               Data       : constant Fixture := Build_Fixture ("projects");
               Store      : Improve.Source.Repository;
               Writer     : Ada_Quality.Storage.Store;
               Empty_Id   : Positive;
               Left_Id    : Positive;
               Right_Id   : Positive;
               Rejected   : Boolean := False;
               Left_Path  : constant String := To_String (Data.Directory) & "/left/shared";
               Right_Path : constant String := To_String (Data.Directory) & "/right/shared";
               Empty_Path : constant String := To_String (Data.Directory) & "/empty";

               procedure Initialize_Crate (Path, Name : String) is
               begin
                  Ada.Directories.Create_Path (Path);
                  Project_Tools.Files.Write_Text_File
                    (Path & "/alire.toml",
                     "name = """ & Name & """" & ASCII.LF &
                     "description = ""source selection fixture""" & ASCII.LF &
                     "version = ""0.1.0-dev""" & ASCII.LF &
                     "authors = [""Improve tests""]" & ASCII.LF &
                     "maintainers = [""Improve tests <tests@example.invalid>""]" & ASCII.LF &
                     "maintainers-logins = [""improve-tests""]" & ASCII.LF &
                     "licenses = ""MIT""" & ASCII.LF &
                     "tags = [""test""]" & ASCII.LF);
               end Initialize_Crate;
            begin
               Initialize_Crate (Left_Path, "left_shared");
               Initialize_Crate (Right_Path, "right_shared");
               Initialize_Crate (Empty_Path, "empty_project");
               Ada_Quality.Storage.Open (Writer, To_String (Data.Database));
               Empty_Id := Ada_Quality.Storage.Add_Project (Writer, Empty_Path);
               Left_Id := Ada_Quality.Storage.Add_Project (Writer, Left_Path);
               Right_Id := Ada_Quality.Storage.Add_Project (Writer, Right_Path);
               Assert (Left_Id /= Right_Id, "distinct project registrations reused an identity");
               Ada_Quality.Storage.Close (Writer);

               Improve.Source.Open (Store, To_String (Data.Database));
               Assert (Improve.Source.Projects (Store).Length = 4, "registered projects were not discovered");
               Assert (Improve.Source.Identity (Store)'Length = 24, "snapshot identity is malformed");
               Assert
                 (Improve.Source.Resolve_Project (Store, To_String (Data.Target)).Id = Data.Project,
                  "canonical project path did not resolve");
               Assert
                 (Improve.Source.Resolve_Project (Store, "improve").Id = Data.Project,
                  "unique project name did not resolve");
               begin
                  declare
                     Value : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, "shared");
                     pragma Unreferenced (Value);
                  begin
                     null;
                  end;
               exception
                  when Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "ambiguous project name was accepted");

               Rejected := False;
               begin
                  declare
                     Value : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, "");
                     pragma Unreferenced (Value);
                  begin
                     null;
                  end;
               exception
                  when Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "empty project selector was accepted");

               Rejected := False;
               begin
                  declare
                     Value : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, "999999999999999999999999999999999999999999");
                     pragma Unreferenced (Value);
                  begin
                     null;
                  end;
               exception
                  when Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "out-of-range project identity was accepted");

               Rejected := False;
               begin
                  declare
                     Project : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, Id_Image (Empty_Id));
                     Value : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
                     pragma Unreferenced (Value);
                  begin
                     null;
                  end;
               exception
                  when Improve.Dependency_Error => Rejected := True;
               end;
               Assert (Rejected, "project without a completed assessment was accepted");

               Improve.Source.Open (Store, To_String (Data.Database));
               Improve.Source.Close (Store);
               Rejected := False;
               begin
                  declare
                     Values : constant Ada_Quality.Reporting.Project_Vectors.Vector := Improve.Source.Projects (Store);
                     pragma Unreferenced (Values);
                  begin
                     null;
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "closed quality repository was readable");
               Remove (Data);
            end;
         when Latest_Completed =>
            declare
               Data  : constant Fixture := Build_Fixture ("latest");
               Store : Improve.Source.Repository;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
                  Chosen : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
               begin
                  Assert (Chosen.Assessment.Run.Id = Data.Run, "newer interrupted run replaced completed baseline");
               end;
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Explicit_Incomplete_Rejected =>
            declare
               Data     : constant Fixture := Build_Fixture ("explicit");
               Store    : Improve.Source.Repository;
               Rejected : Boolean := False;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
               begin
                  begin
                     declare
                        Chosen : constant Improve.Source.Selection :=
                          Improve.Source.Select_Assessment (Store, Project, Data.Interrupted);
                        pragma Unreferenced (Chosen);
                     begin null; end;
                  exception
                     when Improve.Dependency_Error => Rejected := True;
                  end;
               end;
               Assert (Rejected, "explicit interrupted assessment was accepted");
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Normalize_Findings =>
            declare
               Data  : constant Fixture := Build_Fixture ("normalize");
               Store : Improve.Source.Repository;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
                  Chosen : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
                  Values : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Chosen);
               begin
                  Assert (Values.Length = 3, "findings were not deduplicated/classified into three candidates");
                  Assert (To_String (Values.First_Element.Fingerprint) = "fixture-manifest",
                          "Ada Quality finding fingerprint was not preserved");
               end;
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Unknown_Project_Rejected =>
            declare
               Data     : constant Fixture := Build_Fixture ("unknown_project");
               Store    : Improve.Source.Repository;
               Rejected : Boolean := False;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               begin
                  declare
                     Project : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, "not-registered");
                     pragma Unreferenced (Project);
                  begin
                     null;
                  end;
               exception
                  when Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "unknown project was accepted");
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Safe_Path_Validation =>
            Assert (Improve.Findings.Safe_Relative_Path (""), "empty relative path was rejected");
            Assert (Improve.Findings.Safe_Relative_Path ("src/parser.adb"), "safe path was rejected");
            Assert (not Improve.Findings.Safe_Relative_Path ("../outside"), "parent traversal was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path ("src//unit.adb"), "empty path component was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path ("/absolute/path"), "absolute path was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path ("C:\\outside"), "drive path was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path (".."), "terminal parent traversal was accepted");
         when Projects_CLI =>
            declare
               Data   : constant Fixture := Build_Fixture ("projects_cli");
               Result : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("projects|--database|" & To_String (Data.Database) & "|--format|json"));
            begin
               Assert (Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index (To_String (Result.Output),
                       """command"":""projects""") > 0, "projects JSON inspection failed");
               Remove (Data);
            end;
         when Findings_CLI =>
            declare
               Data   : constant Fixture := Build_Fixture ("findings_cli");
               Result : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute
                   (Args ("findings|--database|" & To_String (Data.Database) & "|--project|" &
                          Id_Image (Data.Project) & "|--format|json"));
            begin
               Assert (Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index (To_String (Result.Output),
                       "fixture-manifest") > 0, "findings JSON inspection failed: " & To_String (Result.Errors));
               Remove (Data);
            end;
         when Complete_Strategy_Registry =>
            for Indicator in Ada_Quality.Types.Indicator_Id loop
               declare Strategy : constant Improve.Rules.Remediation_Strategy :=
                 Improve.Rules.Strategy_For (Indicator);
               begin
                  Assert (Strategy.Indicator = Indicator, "strategy registry returned the wrong indicator");
                  Assert (Length (Strategy.Title) > 0 and then Length (Strategy.Acceptance) > 0 and then
                          Length (Strategy.Verification) > 0,
                          "strategy metadata is incomplete for " & Ada_Quality.Types.Image (Indicator));
               end;
            end loop;
            for Kind in Improve.Rules.Strategy_Kind loop
               Assert (Improve.Rules.Image (Kind) /= "", "strategy kind has no stable spelling");
            end loop;
            for Kind in Improve.Model.Candidate_Kind loop
               Assert (Improve.Model.Image (Kind) /= "", "candidate kind has no stable spelling");
            end loop;
            for Value in Improve.Model.Priority loop
               Assert (Improve.Model.Image (Value) /= "", "priority has no stable spelling");
            end loop;
            for Value in Improve.Model.Quality_Outcome loop
               Assert (Improve.Model.Image (Value) /= "", "quality outcome has no stable spelling");
            end loop;
         when Deterministic_Planner =>
            declare
               Data  : constant Fixture := Build_Fixture ("deterministic_plan");
               Store : Improve.Source.Repository;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project  : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
                  Findings : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Selected);
                  First    : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, Findings, Improve.Config.Defaults);
                  Second   : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, Findings, Improve.Config.Defaults);
               begin
                  Assert (First.Fingerprint = Second.Fingerprint, "equivalent planning was not deterministic");
                  Assert (First.Tasks.Length = 3, "fixture did not create three bounded tasks");
                  declare Coverage_Is_Investigation : Boolean := False; begin
                     for Spec of First.Tasks loop
                        if To_String (Spec.Title) = "Investigate missing coverage evidence" then
                           Coverage_Is_Investigation := Spec.Kind = Improve.Model.Investigation_Candidate;
                        end if;
                     end loop;
                     Assert (Coverage_Is_Investigation, "aggregate coverage invented an implementation scope");
                  end;
                  for Spec of First.Tasks loop
                     Assert (Length (Spec.Acceptance) > 0 and then Length (Spec.Scope) > 0,
                             "planner produced an underspecified task");
                  end loop;
               end;
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Planner_Grouping_And_Splitting =>
            declare
               Data  : constant Fixture := Build_Fixture ("planner_split");
               Store : Improve.Source.Repository;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project  : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
                  Original : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Selected);
                  Values   : Improve.Model.Finding_Vectors.Vector;
                  Duplicate : Improve.Model.Finding_Reference := Original.First_Element;
                  Grouped_Settings : constant Improve.Config.Settings := Improve.Config.Defaults;
                  Split_Settings   : Improve.Config.Settings := Improve.Config.Defaults;
               begin
                  Duplicate.Fingerprint := To_Unbounded_String ("second-manifest-finding");
                  Values.Append (Original.First_Element);
                  Values.Append (Duplicate);
                  Split_Settings.Maximum_Findings_Per_Task := 1;
                  declare
                     Grouped : constant Improve.Model.Plan_Revision :=
                       Improve.Planner.Generate (Selected, Values, Grouped_Settings);
                     Split : constant Improve.Model.Plan_Revision :=
                       Improve.Planner.Generate (Selected, Values, Split_Settings);
                  begin
                     Assert (Grouped.Tasks.Length = 1, "related findings were not consolidated");
                     Assert (Grouped.Tasks.First_Element.Finding_Keys.Length = 2,
                             "grouped task lost a finding relationship");
                     Assert (Split.Tasks.Length = 2, "oversized work was not split at the configured limit");
                  end;
               end;
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Dependency_Cycle_Rejected =>
            declare
               procedure Expect_Rejection
                 (Values : Improve.Model.Task_Vectors.Vector;
                  Label  : String) is
                  Rejected : Boolean := False;
               begin
                  begin
                     Improve.Dependencies.Validate (Values);
                  exception
                     when Improve.Data_Error => Rejected := True;
                  end;
                  Assert (Rejected, Label & " was accepted");
               end Expect_Rejection;

               function Make_Task (Identity : String) return Improve.Model.Task_Specification is
                  Result : Improve.Model.Task_Specification;
               begin
                  Result.Id := To_Unbounded_String (Identity);
                  return Result;
               end Make_Task;

               Values : Improve.Model.Task_Vectors.Vector;
               First  : Improve.Model.Task_Specification;
               Second : Improve.Model.Task_Specification;
            begin
               Improve.Dependencies.Validate (Values);
               Values.Append (Make_Task ("IMP-VALID-A"));
               Second := Make_Task ("IMP-VALID-B");
               Second.Dependencies.Append (To_Unbounded_String ("IMP-VALID-A"));
               Values.Append (Second);
               Improve.Dependencies.Validate (Values);

               Values.Clear;
               Values.Append (Make_Task (""));
               Expect_Rejection (Values, "empty task identity");

               Values.Clear;
               Values.Append (Make_Task ("IMP-DUP"));
               Values.Append (Make_Task ("IMP-DUP"));
               Expect_Rejection (Values, "duplicate task identity");

               Values.Clear;
               First := Make_Task ("IMP-UNKNOWN");
               First.Dependencies.Append (To_Unbounded_String ("IMP-MISSING"));
               Values.Append (First);
               Expect_Rejection (Values, "unknown dependency");

               Values.Clear;
               First := Make_Task ("IMP-SELF");
               First.Dependencies.Append (First.Id);
               Values.Append (First);
               Expect_Rejection (Values, "self dependency");

               Values.Clear;
               First := Make_Task ("IMP-EDGE");
               First.Dependencies.Append (To_Unbounded_String ("IMP-TARGET"));
               First.Dependencies.Append (To_Unbounded_String ("IMP-TARGET"));
               Values.Append (First);
               Values.Append (Make_Task ("IMP-TARGET"));
               Expect_Rejection (Values, "duplicate dependency edge");

               Values.Clear;
               First := Make_Task ("IMP-A");
               First.Dependencies.Append (To_Unbounded_String ("IMP-B"));
               Second := Make_Task ("IMP-B");
               Second.Dependencies.Append (To_Unbounded_String ("IMP-A"));
               Values.Append (First);
               Values.Append (Second);
               Expect_Rejection (Values, "dependency cycle");
            end;
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
               declare Values : constant Improve.Storage.Summary_Vectors.Vector := Improve.Storage.List (Store); begin
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
                    Improve.Planner.Generate (Selected, Improve.Findings.Normalize (Selected), Improve.Config.Defaults);
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
               Directory : constant String := "/tmp/improve_phase4_read_only";
               State     : constant String := Directory & "/missing.db";
               Result    : Improve.CLI.Outcome;
            begin
               Project_Tools.Files.Delete_Tree (Directory);
               Ada.Directories.Create_Directory (Directory);
               Result := Improve.CLI.Execute (Args ("plan|show|PLAN-000001|--state|" & State));
               Assert (Result.Exit_Code = Improve.CLI.Unavailable_Exit and then not Ada.Directories.Exists (State),
                       "read-only plan inspection initialized missing state");
               Project_Tools.Files.Delete_Tree (Directory);
            end;
         when Plan_Approval_Required =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("approval_required", Harness_Project => True);
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
               Data    : constant Fixture := Build_Fixture ("source_stale", Harness_Project => True);
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
               Data   : constant Fixture := Build_Fixture ("measurement_source_mismatch", Harness_Project => True);
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
               First   : constant Fixture := Build_Fixture ("identity_first", Harness_Project => True);
               Second  : constant Fixture := Build_Fixture ("identity_second", Harness_Project => True);
               State   : constant String := To_String (First.Directory) & "/improve.db";
               Planned : constant Improve.CLI.Outcome := Prepare_Verification_Plan (First, State);
               Applied : Improve.CLI.Outcome;
               Verified : Improve.CLI.Outcome;
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
               Remove (First);
               Remove (Second);
            end;
         when Quality_Database_Histories_Isolated =>
            declare
               First       : constant Fixture := Build_Fixture ("history_first", Harness_Project => True);
               Second      : constant Fixture := Build_Fixture ("history_second", Harness_Project => True);
               State_Path  : constant String := To_String (First.Directory) & "/improve.db";
               First_Plan  : constant Improve.CLI.Outcome := Prepare_Verification_Plan (First, State_Path);
               Second_Plan : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Second, State_Path);
               Store       : Improve.Storage.Store;
            begin
               Assert
                 (First.Project = Second.Project and then First_Plan.Exit_Code = 0 and then Second_Plan.Exit_Code = 0,
                  "same-numbered database history fixture did not plan");
               Improve.Storage.Open (Store, State_Path, Writable => False);
               Assert
                 (Improve.Storage.List (Store).Length = 2 and then
                  Improve.Storage.List
                    (Store, Draft_For (First).Project).Length = 1 and then
                  Improve.Storage.List
                    (Store, Draft_For (Second).Project).Length = 1,
                  "same numeric project IDs shared remediation history");
               Improve.Storage.Close (Store);
               Remove (First);
               Remove (Second);
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
                  Ada.Strings.Fixed.Index (To_String (Inspected.Output), "IMP-000001") > 0,
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
         when Native_Publication_And_Recovery =>
            declare
               package Errors renames Model_Runner.Errors;
               package Records renames Model_Runner.Framework.Records;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data    : constant Fixture := Build_Fixture ("native_publication", Harness_Project => True);
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
         when Selective_Publication_Resolves_Dependency =>
            declare
               package Errors renames Model_Runner.Errors;
               package Records renames Model_Runner.Framework.Records;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("selective_dependency", Harness_Project => True);
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
         when Refresh_Reconciles_State =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("refresh_state", Harness_Project => True);
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
                  declare Values : constant Improve.Storage.Verification_Vectors.Vector :=
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
                     if Evidence.Scope = Improve.Storage.Task_Evaluation then
                        Assert
                          (Evidence.Outcome = Improve.Model.Verified,
                           "task verification outcome was not preserved");
                     elsif Evidence.Scope = Improve.Storage.Plan_Evaluation then
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
            begin
               for Index in 1 .. Natural (First.Tasks.Length) loop
                  if First.Tasks (Index).Finding_Keys.Contains (To_Unbounded_String ("fixture-manifest")) then
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
                  if Evidence.Scope = Improve.Storage.Plan_Evaluation then
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
         when Agent_Context_Bounded =>
            declare
               Data     : constant Fixture := Build_Fixture ("agent_context", Harness_Project => True);
               Draft    : constant Improve.Model.Plan_Revision := Draft_For (Data);
               Settings : Improve.Config.Settings := Improve.Config.Defaults;
            begin
               Settings.Agent_Max_Context_Bytes := 8_192;
               Settings.Agent_Max_File_Bytes := 256;
               declare Context : constant Improve.Refinement.Planning_Context :=
                 Improve.Refinement.Build_Context (Draft, Settings, Existing_Tasks => Draft.Tasks);
               begin
                  Assert (Context.Byte_Count <= Settings.Agent_Max_Context_Bytes,
                          "agent context exceeded its configured byte limit");
                  Assert (Length (Context.Evidence) > 0 and then Length (Context.Draft_Tasks) > 0 and then
                            Length (Context.Existing_Tasks) > 0 and then Length (Context.Required_Schema) > 0,
                          "agent context omitted required planning material");
                  Assert (not Context.Sources.Is_Empty and then
                            Context.Sources.First_Element.State = Improve.Refinement.Source_Available,
                          "agent context did not include safely rooted source evidence");
               end;
               declare
                  Path     : constant String := To_String (Data.Directory) & "/invalid-agent.toml";
                  Rejected : Boolean := False;
               begin
                  Project_Tools.Files.Write_Text_File
                    (Path, "schema_version = 1" & Character'Val (10) &
                       "agent_max_context_bytes = 512" & Character'Val (10));
                  begin
                     declare
                        Value : constant Improve.Config.Settings := Improve.Config.Load (Path);
                        pragma Unreferenced (Value);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Argument_Error => Rejected := True;
                  end;
                  Assert (Rejected, "invalid agent context limit was accepted");
               end;
               Remove (Data);
            end;
         when Agent_Valid_Refinement =>
            declare
               Data     : constant Fixture := Build_Fixture ("agent_valid", Harness_Project => True);
               Draft    : constant Improve.Model.Plan_Revision := Draft_For (Data);
               Settings : constant Improve.Config.Settings := Improve.Config.Defaults;
               Provider : aliased Fake_Adapter :=
                 (Mode => Valid_Agent, Draft => Draft,
                  Expected_Limit => Settings.Agent_Max_Context_Bytes, others => <>);
               Result   : constant Improve.Refinement.Refinement_Result :=
                 Improve.Refinement.Refine (Draft, Settings, Provider'Access);
            begin
               Assert (Result.Status = Improve.Refinement.Refined, "valid agent refinement was not applied");
               Assert (Result.Plan.Fingerprint /= Draft.Fingerprint and then Provider.Saw_Bounded and then
                         Provider.Saw_Source,
                       "refined plan lost provenance or bounded source context");
               Assert (To_String (Result.Plan.Tasks.First_Element.Title) = "Focused remediation",
                       "agent title refinement was not applied");
               Assert (Ada.Strings.Fixed.Index
                         (To_String (Result.Plan.Tasks.First_Element.Acceptance),
                          To_String (Draft.Tasks.First_Element.Acceptance)) = 1,
                       "agent refinement weakened deterministic acceptance");
               declare
                  Again_Provider : aliased Fake_Adapter :=
                    (Mode => Valid_Agent, Draft => Draft,
                     Expected_Limit => Settings.Agent_Max_Context_Bytes, others => <>);
                  Again : constant Improve.Refinement.Refinement_Result :=
                    Improve.Refinement.Refine (Draft, Settings, Again_Provider'Access);
                  State : Improve.Storage.Store;
                  Saved : Improve.Storage.Save_Result;
               begin
                  Assert (Again.Plan.Fingerprint = Result.Plan.Fingerprint,
                          "identical agent refinement was not deterministic");
                  Improve.Storage.Open
                    (State, To_String (Data.Directory) & "/agent-improve.db", Writable => True);
                  Saved := Improve.Storage.Save (State, Result.Plan);
                  Improve.Storage.Close (State);
                  Assert (not Saved.Existing and then Saved.Plan.Tasks.First_Element.Title =
                            Result.Plan.Tasks.First_Element.Title,
                          "validated agent refinement did not persist as a normal plan revision");
               end;
               Remove (Data);
            end;
         when Agent_Malformed_Fallback =>
            Check_Agent_Fallback
              (Malformed_Agent, Improve.Refinement.Malformed_Fallback, "malformed");
         when Agent_Missing_File_Rejected =>
            Check_Agent_Fallback
              (Missing_File_Agent, Improve.Refinement.Rejected_Fallback, "missing_file");
         when Agent_Invented_Evidence_Rejected =>
            Check_Agent_Fallback
              (Invented_Evidence_Agent, Improve.Refinement.Rejected_Fallback, "invented_evidence");
         when Agent_Invalid_Category_Rejected =>
            Check_Agent_Fallback
              (Invalid_Category_Agent, Improve.Refinement.Rejected_Fallback, "invalid_category");
         when Agent_Cycle_Rejected =>
            Check_Agent_Fallback
              (Cyclic_Agent, Improve.Refinement.Rejected_Fallback, "cycle");
         when Agent_Timeout_Fallback =>
            Check_Agent_Fallback
              (Slow_Agent, Improve.Refinement.Timeout_Fallback, "timeout");
         when Agent_Unavailable_Fallback =>
            Check_Agent_Fallback
              (Unavailable_Agent, Improve.Refinement.Unavailable_Fallback, "unavailable");
         when Agent_Weakening_Rejected =>
            Check_Agent_Fallback
              (Weakening_Agent, Improve.Refinement.Rejected_Fallback, "weakening");
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
                         (To_String (One.Output), """outstanding"":3") > 0 and then Ada.Strings.Fixed.Index
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
                  "require_initialized_project = false" & ASCII.LF &
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
                     Value.Color = Improve.Config.Color_Never and then
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
            begin
               Assert (Planned.Exit_Code = 0, "terminal-path fixture planning failed");
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
                  Outcome       : Improve.Model.Quality_Outcome := Improve.Model.Unverified) is
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
                  Views := Improve.Tasks.Build (Plan, Publications, Evidence);
                  Assert (Views.First_Element.Status = Expected, "unexpected operational task status");
               end Check;
            begin
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
      end case;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      for Id in Test_Id loop
         declare
            Item : constant Case_Access := new Case_Test (Id);
         begin
            Result.Add_Test (Item);
         end;
      end loop;
      return Result;
   end Suite;
end Improve_Test_Suite;
