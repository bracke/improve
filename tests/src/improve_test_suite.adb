with Ada.Directories;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Exceptions;
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
with Improve.Refinement;
with Improve.Rules;
with Improve.Source;
with Improve.Storage;
with Improve.Text;
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
   use type Improve.Model.Candidate_Kind;
   use type Improve.Model.Task_Vectors.Vector;
   use type Improve.Refinement.Refinement_Status;
   use type Improve.Refinement.Source_State;
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
      Native_Publication_And_Recovery, Refresh_Reconciles_State, Verification_Resolved, Verification_Still_Failing,
      Verification_Partially_Resolved, Verification_Missing_Evidence, Verification_Regressed,
      Verification_Policy_Changed, Verification_Incomplete_Rejected, Agent_Context_Bounded,
      Agent_Valid_Refinement, Agent_Malformed_Fallback, Agent_Missing_File_Rejected,
      Agent_Invented_Evidence_Rejected, Agent_Invalid_Category_Rejected, Agent_Cycle_Rejected,
      Agent_Timeout_Fallback, Agent_Unavailable_Fallback, Agent_Weakening_Rejected);

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
      Run := Ada_Quality.Storage.Start_Assessment (Store, Project, "source-a", "policy-a");
      Value.Id := Run;
      Value.Project_Id := Project;
      Value.Project_Path := To_Unbounded_String (Target);
      Value.Source_Fingerprint := To_Unbounded_String ("source-a");
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

   type Followup_State is (All_Pass, Structure_Failing, Structure_Unmeasurable);

   function Publish_Followup
     (Data            : Fixture;
      Structure_State : Followup_State := All_Pass;
      Policy           : String := "policy-a";
      Source           : String := "source-c";
      Toolchain        : String := "gnat-15.2.1") return Positive is
      use Ada_Quality.Types;
      Store : Ada_Quality.Storage.Store;
      Run   : Positive;
      Value : Assessment;
   begin
      Ada_Quality.Storage.Open (Store, To_String (Data.Database));
      Run := Ada_Quality.Storage.Start_Assessment (Store, Data.Project, Source, Policy);
      Value.Id := Run;
      Value.Project_Id := Data.Project;
      Value.Project_Path := Data.Target;
      Value.Source_Fingerprint := To_Unbounded_String (Source);
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
                Level         => High,
                Message       => To_Unbounded_String ("manifest is invalid"),
                Relative_Path => To_Unbounded_String ("alire.toml"),
                Line          => 1,
                Fingerprint   => To_Unbounded_String ("fixture-manifest")));
            Value.Results.Replace_Element (Value.Results.First_Index, Structure);
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
         when Catalog => Assert (Improve.Text.Catalog_Is_Valid, "message catalog is invalid");
         when Digest => Assert (Improve.Stable_Digest ("improve") = Improve.Stable_Digest ("improve") and then
                                Improve.Stable_Digest ("improve") /= Improve.Stable_Digest ("Improve"),
                                "stable digest is not deterministic or discriminating");
         when Project_Discovery =>
            declare
               Data  : constant Fixture := Build_Fixture ("projects");
               Store : Improve.Source.Repository;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               Assert (Improve.Source.Projects (Store).Length = 1, "registered project was not discovered");
               Assert (Improve.Source.Identity (Store)'Length = 24, "snapshot identity is malformed");
               Improve.Source.Close (Store);
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
            Assert (Improve.Findings.Safe_Relative_Path ("src/parser.adb"), "safe path was rejected");
            Assert (not Improve.Findings.Safe_Relative_Path ("../outside"), "parent traversal was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path ("src//unit.adb"), "empty path component was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path ("/absolute/path"), "absolute path was accepted");
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
               Values   : Improve.Model.Task_Vectors.Vector;
               First    : Improve.Model.Task_Specification;
               Second   : Improve.Model.Task_Specification;
               Rejected : Boolean := False;
            begin
               First.Id := To_Unbounded_String ("IMP-A");
               First.Dependencies.Append (To_Unbounded_String ("IMP-B"));
               Second.Id := To_Unbounded_String ("IMP-B");
               Second.Dependencies.Append (To_Unbounded_String ("IMP-A"));
               Values.Append (First);
               Values.Append (Second);
               begin
                  Improve.Dependencies.Validate (Values);
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "dependency cycle was accepted");
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
               Initialize_Harness (To_String (Data.Target));
               Plan_Result := Improve.CLI.Execute
                 (Args ("plan|--database|" & To_String (Data.Database) & "|--state|" & State & "|--project|" &
                        Id_Image (Data.Project) & "|--format|json"));
               Assert (Plan_Result.Exit_Code = 0, "publication fixture plan failed: " & To_String (Plan_Result.Errors));
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
               Initialize_Harness (To_String (Data.Target));
               Planned := Prepare_Verification_Plan (Data, State);
               Assert (Planned.Exit_Code = 0, "refresh fixture plan failed");
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
                     Assert (Values.Length = 3, "repeated verification duplicated historical evidence");
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
