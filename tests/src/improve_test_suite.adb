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
with Improve_CLI_Test_Suite;
with Improve_Planning_Test_Suite;
with Improve_Source_Test_Suite;
with Improve_Storage_Test_Suite;
with Improve_Tasks_Test_Suite;
with Improve.Config;
with Improve.Dependencies;
with Improve.Findings;
with Improve.Model;
with Improve.Operations.Inspection;
with Improve.Operations.Planning;
with Improve.Planner;
with Improve.Presentation;
with Improve.Refinement;
with Improve.Recovery;
with Improve.Rules;
with Improve.Source;
with Improve.Storage;
with Improve.Tasks;
with Improve.Text;
with Improve.Workflow;
with Model_Runner.Errors;
with Model_Runner.Framework.Configuration_Records;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Schemas;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Task_Eligibility;
with Model_Runner.Framework.Tasks;
with Project_Tools.Files;

package body Improve_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Improve.Config.Color_Mode;
   use type Improve.Config.Output_Format;
   use type Improve.Config.Severity_Level;
   use type Improve.Model.Candidate_Kind;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Model.Task_Vectors.Vector;
   use type Improve.Refinement.Refinement_Status;
   use type Improve.Refinement.Source_State;
   use type Improve.Storage.Verification_Scope;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Types.Indicator_Id;

   type Test_Id is
     (Catalog, Digest,
      Project_Discovery, Latest_Completed, Explicit_Incomplete_Rejected, Normalize_Findings,
      Unknown_Project_Rejected, Safe_Path_Validation, Projects_CLI, Findings_CLI,
      Complete_Strategy_Registry, Deterministic_Planner, Planner_Grouping_And_Splitting,
      Plan_Fingerprint_Severity_Sensitive, Plan_Fingerprint_Ignores_Unrelated_Snapshot,
      Dependency_Cycle_Rejected, Dense_Contract_Fingerprints, Plan_Dry_Run_CLI, Persistent_Plan_Roundtrip,
      Repeated_Plan_Idempotent, Persisted_Dependency_Translation, Read_Only_Does_Not_Initialize,
      Storage_Finalizes_On_Error,
      Plan_Approval_Required, Current_Source_Staleness_Detected, Historical_Task_Lookup,
      Measurement_Source_Mismatch_Blocks_Plan, Quality_Database_Identity_Rejected,
      Quality_Database_Histories_Isolated, Publication_Policy_Change_Rejected,
      Native_Publication_And_Recovery, Native_Task_Contract_Fidelity, Changed_Task_Contract_Replaced,
      Replacement_Running_And_Completed, Workspace_Lifecycle_Fails_Closed,
      Selective_Publication_Resolves_Dependency, Prerequisite_Replacement_Migrates_Dependents,
      Refresh_Reconciles_State,
      Verification_Resolved, Verification_Still_Failing,
      Verification_Task_Scope_Not_Project, Verification_Severity_Drop_Outstanding,
      Verification_Partially_Resolved, Verification_Missing_Evidence, Verification_Regressed,
      Unrelated_Critical_Project_Regression, Out_Of_Order_Verification_Not_Regression,
      Changed_Contract_Not_Regression, Verification_Policy_Changed, Verification_Incomplete_Rejected,
      Verification_Revisions_Coexist,
      Agent_Context_Bounded,
      Agent_Valid_Refinement, Agent_Malformed_Fallback, Agent_Missing_File_Rejected,
      Agent_Invented_Evidence_Rejected, Agent_Invalid_Category_Rejected, Agent_Cycle_Rejected,
      Agent_Timeout_Fallback, Agent_Unavailable_Fallback, Agent_Weakening_Rejected,
      Tasks_CLI_Golden, Tasks_JSON_Filter, Status_Project_And_All, Status_Verification_Freshness,
      Status_All_Mixed_Freshness, Interrupted_Publication_Recovery,
      Recovery_Rejects_Stale_Uncommitted,
      Published_Task_Reused_Across_Revisions, Recovery_Uses_Exact_Revision,
      Recovery_Limit_Enforced, Recover_Missing_State, Configuration_Bounds,
      Operational_Terminal_Paths, Real_End_To_End_Workflow);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding function Name (Item : Case_Test) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Case_Test);

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_" & Test_Id'Image (Item.Id)));

   function Execution_Available
     (Item : Model_Runner.Framework.Stores.Store; Task_Id : String) return String is
      pragma Unreferenced (Item, Task_Id);
   begin
      return "";
   end Execution_Available;

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
      Multiple_Structure : Boolean := False;
      Second_Structure_Severity : Ada_Quality.Types.Severity := Ada_Quality.Types.High) return Fixture is
      use Ada_Quality.Types;
      Directory : constant String := "/tmp/improve_phase2_" & Label;
      DB_Path   : constant String := Directory & "/quality.db";
      Store     : Ada_Quality.Storage.Store;
      Project   : Positive;
      Run       : Positive;
      Later     : Positive;
      Value     : Assessment;
      Target    : constant String := Directory & "/project";
      pragma Unreferenced (Harness_Project);
   begin
      Project_Tools.Files.Delete_Tree (Directory);
      Ada.Directories.Create_Directory (Directory);
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
                  Level         => Second_Structure_Severity,
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
      package Config renames Model_Runner.Framework.Configuration_Records;
      package Errors renames Model_Runner.Errors;
      package Records renames Model_Runner.Framework.Records;
      package Schemas renames Model_Runner.Framework.Schemas;
      package Stores renames Model_Runner.Framework.Stores;
      Store    : Stores.Store;
      Initial  : Stores.Transaction;
      Resolved : Records.Item := Records.Create (Schemas.Configuration_Schema, 1, "CONFIG", 1);
      Status   : Errors.Error_Info;
   begin
      Records.Set (Resolved, "template_id", "improve-tests");
      Records.Set (Resolved, "template_version", "1");
      Records.Set (Resolved, "template_fingerprint", "fixture");
      Records.Set (Resolved, "template_origin", "Improve tests");
      Records.Set (Resolved, "template_order", "improve-tests");
      Records.Set (Resolved, "task_kind.remediation", "acceptance, notes?");
      Records.Set (Resolved, "configuration_fingerprint", Config.Fingerprint (Resolved));
      Stores.Put (Initial, Model_Runner.Framework.Config_Area, "resolved", Resolved);
      Stores.Create (Store, Directory, "Improve tests", Status, Initial);
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

   procedure Run_Agent_Test (Item : in out Case_Test) is separate;
   procedure Run_Operations_Test (Item : in out Case_Test) is separate;
   procedure Run_Publication_Test (Item : in out Case_Test) is separate;
   procedure Run_Verification_Test (Item : in out Case_Test) is separate;

   overriding procedure Run_Test (Item : in out Case_Test) is
   begin
      case Item.Id is
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
         when Digest =>
            Assert
              (Improve.Stable_Digest ("") =
                 "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" and then
               Improve.Stable_Digest ("improve") = Improve.Stable_Digest ("improve") and then
               Improve.Stable_Digest ("improve") /= Improve.Stable_Digest ("Improve"),
               "SHA-256 stable digest is incorrect or nondeterministic");
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
                 (Improve.Source.Resolve_Project (Store, "project").Id = Data.Project,
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
                  begin
                     Assert
                       (Improve.Source.Latest_Completed_Run (Store, Project) = 0,
                        "empty project reported a completed assessment");
                     declare
                        Value : constant Improve.Source.Selection :=
                          Improve.Source.Select_Assessment (Store, Project);
                        pragma Unreferenced (Value);
                     begin
                        null;
                     end;
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
         when Plan_Fingerprint_Severity_Sensitive =>
            declare
               Data    : constant Fixture := Build_Fixture
                 ("severity_fingerprint", Harness_Project => True, Multiple_Structure => True,
                  Second_Structure_Severity => Ada_Quality.Types.Low);
               Quality : Improve.Source.Repository;
               Low_Settings  : Improve.Config.Settings := Improve.Config.Defaults;
               High_Settings : Improve.Config.Settings := Improve.Config.Defaults;
               Store   : Improve.Storage.Store;
               First   : Improve.Storage.Save_Result;
               Second  : Improve.Storage.Save_Result;
            begin
               Low_Settings.Minimum_Severity := Improve.Config.Low;
               High_Settings.Minimum_Severity := Improve.Config.High;
               Improve.Source.Open (Quality, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Quality, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection :=
                    Improve.Source.Select_Assessment (Quality, Project, Data.Run);
                  Low_Findings : constant Improve.Model.Finding_Vectors.Vector :=
                    Improve.Findings.Normalize (Selected, Ada_Quality.Types.Low, True);
                  High_Findings : constant Improve.Model.Finding_Vectors.Vector :=
                    Improve.Findings.Normalize (Selected, Ada_Quality.Types.High, True);
                  Low_Plan : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, Low_Findings, Low_Settings);
                  High_Plan : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, High_Findings, High_Settings);
               begin
                  Improve.Source.Close (Quality);
                  Assert
                    (Low_Findings.Length > High_Findings.Length and then
                     Low_Plan.Fingerprint /= High_Plan.Fingerprint,
                     "severity-dependent finding membership collided in the plan fingerprint");
                  Improve.Storage.Open
                    (Store, To_String (Data.Directory) & "/severity-improve.db", Writable => True);
                  First := Improve.Storage.Save (Store, Low_Plan);
                  Second := Improve.Storage.Save (Store, High_Plan);
                  Improve.Storage.Close (Store);
                  Assert
                    (not First.Existing and then not Second.Existing and then Second.Plan.Revision = 2 and then
                     Second.Plan.Findings.Length = High_Findings.Length,
                     "changed severity threshold silently returned an older plan revision");
               end;
               Remove (Data);
            end;
         when Plan_Fingerprint_Ignores_Unrelated_Snapshot =>
            declare
               Data       : constant Fixture := Build_Fixture ("unrelated_snapshot", Harness_Project => True);
               Quality    : Improve.Source.Repository;
               State_Path : constant String := To_String (Data.Directory) & "/snapshot-improve.db";
               First_Plan : Improve.Model.Plan_Revision;
               First_Save : Improve.Storage.Save_Result;
               Second_Save : Improve.Storage.Save_Result;
               First_Snapshot : Unbounded_String;
            begin
               Improve.Source.Open (Quality, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Quality, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection :=
                    Improve.Source.Select_Assessment (Quality, Project, Data.Run);
                  Findings : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Selected);
               begin
                  First_Plan := Improve.Planner.Generate (Selected, Findings, Improve.Config.Defaults);
                  First_Snapshot := Selected.Baseline.Snapshot_Id;
               end;
               Improve.Source.Close (Quality);
               declare State : Improve.Storage.Store; begin
                  Improve.Storage.Open (State, State_Path, Writable => True);
                  First_Save := Improve.Storage.Save (State, First_Plan);
                  Improve.Storage.Close (State);
               end;
               declare Other : constant Fixture := Add_Fixture_Project (Data, "unrelated_project"); begin
                  Assert (Other.Project /= Data.Project, "unrelated project did not receive a separate identity");
               end;
               Improve.Source.Open (Quality, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Quality, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection :=
                    Improve.Source.Select_Assessment (Quality, Project, Data.Run);
                  Findings : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Selected);
                  Second_Plan : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, Findings, Improve.Config.Defaults);
               begin
                  Assert
                    (Selected.Baseline.Snapshot_Id /= First_Snapshot and then
                     Second_Plan.Fingerprint = First_Plan.Fingerprint,
                     "unrelated quality database state changed semantic plan identity");
                  Improve.Source.Close (Quality);
                  declare State : Improve.Storage.Store; begin
                     Improve.Storage.Open (State, State_Path, Writable => True);
                     Second_Save := Improve.Storage.Save (State, Second_Plan);
                     Improve.Storage.Close (State);
                  end;
               end;
               Assert
                 (not First_Save.Existing and then Second_Save.Existing and then Second_Save.Plan.Revision = 1,
                  "unrelated assessment created an unnecessary plan revision");
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
         when Dense_Contract_Fingerprints =>
            declare
               Plan : Improve.Model.Plan_Revision;
            begin
               for Index in 1 .. 32 loop
                  declare
                     Spec : Improve.Model.Task_Specification;
                  begin
                     Spec.Id := To_Unbounded_String ("IMP-DENSE-" & Id_Image (Index));
                     Spec.Title := Spec.Id;
                     Spec.Acceptance := To_Unbounded_String ("complete");
                     for Dependency in 1 .. Index - 1 loop
                        Spec.Dependencies.Append
                          (To_Unbounded_String ("IMP-DENSE-" & Id_Image (Dependency)));
                     end loop;
                     Plan.Tasks.Append (Spec);
                  end;
               end loop;
               declare
                  First : constant Improve.Model.Task_Contract_Binding_Vectors.Vector :=
                    Improve.Model.Effective_Task_Contracts (Plan);
                  Second : constant Improve.Model.Task_Contract_Binding_Vectors.Vector :=
                    Improve.Model.Effective_Task_Contracts (Plan);
               begin
                  Assert
                    (First.Length = Plan.Tasks.Length and then
                     First.Last_Element.Fingerprint = Second.Last_Element.Fingerprint,
                     "dense dependency contracts were not calculated deterministically");
               end;
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
         when Storage_Finalizes_On_Error =>
            declare
               Directory : constant String := "/tmp/improve_storage_finalize";
               State     : constant String := Directory & "/state.db";
               Rejected  : Boolean := False;
            begin
               Project_Tools.Files.Delete_Tree (Directory);
               Ada.Directories.Create_Directory (Directory);
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
               Second_Task : Unbounded_String;
               Listed      : Improve.CLI.Outcome;
               Rejected    : Improve.CLI.Outcome;
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
               Data    : constant Fixture := Build_Fixture ("publication_policy", Harness_Project => True);
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
         when Native_Publication_And_Recovery | Native_Task_Contract_Fidelity |
              Changed_Task_Contract_Replaced | Replacement_Running_And_Completed |
              Workspace_Lifecycle_Fails_Closed | Selective_Publication_Resolves_Dependency |
              Prerequisite_Replacement_Migrates_Dependents | Refresh_Reconciles_State =>
            Run_Publication_Test (Item);
         when Verification_Resolved | Verification_Still_Failing | Verification_Task_Scope_Not_Project |
              Verification_Severity_Drop_Outstanding | Verification_Partially_Resolved |
              Verification_Missing_Evidence | Verification_Regressed | Unrelated_Critical_Project_Regression |
              Out_Of_Order_Verification_Not_Regression | Changed_Contract_Not_Regression |
              Verification_Policy_Changed | Verification_Incomplete_Rejected | Verification_Revisions_Coexist =>
            Run_Verification_Test (Item);
         when Agent_Context_Bounded | Agent_Valid_Refinement | Agent_Malformed_Fallback |
              Agent_Missing_File_Rejected | Agent_Invented_Evidence_Rejected | Agent_Invalid_Category_Rejected |
              Agent_Cycle_Rejected | Agent_Timeout_Fallback | Agent_Unavailable_Fallback |
              Agent_Weakening_Rejected =>
            Run_Agent_Test (Item);
         when Tasks_CLI_Golden | Tasks_JSON_Filter | Status_Project_And_All |
              Status_Verification_Freshness | Status_All_Mixed_Freshness | Interrupted_Publication_Recovery |
              Recovery_Rejects_Stale_Uncommitted | Published_Task_Reused_Across_Revisions |
              Recovery_Uses_Exact_Revision | Recovery_Limit_Enforced | Recover_Missing_State |
              Configuration_Bounds | Operational_Terminal_Paths |
              Real_End_To_End_Workflow =>
            Run_Operations_Test (Item);
      end case;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Improve_CLI_Test_Suite.Suite);
      Result.Add_Test (Improve_Planning_Test_Suite.Suite);
      Result.Add_Test (Improve_Source_Test_Suite.Suite);
      Result.Add_Test (Improve_Storage_Test_Suite.Suite);
      Result.Add_Test (Improve_Tasks_Test_Suite.Suite);
      for Id in Test_Id loop
         declare
            Item : constant Case_Access := new Case_Test (Id);
         begin
            Result.Add_Test (Item);
         end;
      end loop;
      return Result;
   end Suite;
begin
   Model_Runner.Framework.Task_Eligibility.Register (Execution_Available'Access);
end Improve_Test_Suite;
