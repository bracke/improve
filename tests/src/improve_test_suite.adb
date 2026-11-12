with Ada.Directories;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
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
with Improve_Operations_Test_Suite;
with Improve_Publication_Test_Suite;
with Improve_Source_Test_Suite;
with Improve_Storage_Test_Suite;
with Improve_Storage_Codec_Test_Suite;
with Improve_Tasks_Test_Suite;
with Improve_Test_Support;
with Improve_Verification_Test_Suite;
with Improve.Config;
with Improve.Dependencies;
with Improve.Findings;
with Improve.Model;
with Improve.Operations;
with Improve.Operations.Planning;
with Improve.Planner;
with Improve.Presentation;
with Improve.Refinement;
with Improve.Rules;
with Improve.Source;
with Improve.Storage;
with Improve.Text;
with Hostkit.Fs;
with Model_Runner.Errors;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Task_Eligibility;
with Model_Runner.Framework.Tasks;
with Project_Tools.Files;

package body Improve_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Improve_Test_Support;
   use type Improve.Config.Color_Mode;
   use type Improve.Config.Output_Format;
   use type Improve.Config.Severity_Level;
   use type Improve.Model.Candidate_Kind;
   use type Improve.Model.Task_Vectors.Vector;
   use type Improve.Refinement.Refinement_Status;
   use type Improve.Refinement.Source_State;
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
      Agent_Context_Bounded,
      Agent_Valid_Refinement, Agent_Malformed_Fallback, Agent_Missing_File_Rejected,
      Agent_Invented_Evidence_Rejected, Agent_Invalid_Category_Rejected, Agent_Cycle_Rejected,
      Agent_Timeout_Fallback, Agent_Unavailable_Fallback, Agent_Weakening_Rejected,
      Agent_Oversized_Collection_Rejected);

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


   type Fake_Mode is
     (Valid_Agent, Malformed_Agent, Missing_File_Agent, Invented_Evidence_Agent, Invalid_Category_Agent,
      Cyclic_Agent, Slow_Agent, Unavailable_Agent, Weakening_Agent, Oversized_Collection_Agent);

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
         when Slow_Agent =>
            Response.Status := Improve.Refinement.Agent_Timed_Out;
            Response.Diagnostic := To_Unbounded_String ("fixture adapter deadline expired");
            return;
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
            Proposal.Title := Base.Title;
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
         when Oversized_Collection_Agent =>
            for Index in 1 .. 51 loop
               Response.Proposals (1).Relevant_Files.Append (To_Unbounded_String ("src/extra-" & Id_Image (Index)));
            end loop;
         when others => null;
      end case;
   end Request;

   procedure Check_Agent_Fallback
     (Mode     : Fake_Mode;
      Expected : Improve.Refinement.Refinement_Status;
      Label    : String) is
      Data     : constant Fixture := Build_Fixture ("agent_" & Label);
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

   procedure Run_Domain_Test (Item : in out Case_Test) is separate;
   procedure Run_Integration_Test (Item : in out Case_Test) is separate;

   overriding procedure Run_Test (Item : in out Case_Test) is
   begin
      case Item.Id is
         when Catalog | Digest | Project_Discovery | Latest_Completed | Explicit_Incomplete_Rejected |
           Normalize_Findings | Unknown_Project_Rejected | Safe_Path_Validation | Projects_CLI | Findings_CLI |
           Complete_Strategy_Registry | Deterministic_Planner | Planner_Grouping_And_Splitting |
           Plan_Fingerprint_Severity_Sensitive | Plan_Fingerprint_Ignores_Unrelated_Snapshot |
           Dependency_Cycle_Rejected | Dense_Contract_Fingerprints =>
            Run_Domain_Test (Item);
         when Plan_Dry_Run_CLI | Persistent_Plan_Roundtrip | Repeated_Plan_Idempotent |
           Persisted_Dependency_Translation | Read_Only_Does_Not_Initialize | Storage_Finalizes_On_Error |
           Plan_Approval_Required | Current_Source_Staleness_Detected | Historical_Task_Lookup |
           Measurement_Source_Mismatch_Blocks_Plan | Quality_Database_Identity_Rejected |
           Quality_Database_Histories_Isolated | Publication_Policy_Change_Rejected =>
            Run_Integration_Test (Item);
         when Agent_Context_Bounded | Agent_Valid_Refinement | Agent_Malformed_Fallback |
           Agent_Missing_File_Rejected | Agent_Invented_Evidence_Rejected | Agent_Invalid_Category_Rejected |
           Agent_Cycle_Rejected | Agent_Timeout_Fallback | Agent_Unavailable_Fallback | Agent_Weakening_Rejected |
           Agent_Oversized_Collection_Rejected =>
            Run_Agent_Test (Item);
      end case;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Improve_CLI_Test_Suite.Suite);
      Result.Add_Test (Improve_Operations_Test_Suite.Suite);
      Result.Add_Test (Improve_Planning_Test_Suite.Suite);
      Result.Add_Test (Improve_Publication_Test_Suite.Suite);
      Result.Add_Test (Improve_Source_Test_Suite.Suite);
      Result.Add_Test (Improve_Storage_Test_Suite.Suite);
      Result.Add_Test (Improve_Storage_Codec_Test_Suite.Suite);
      Result.Add_Test (Improve_Tasks_Test_Suite.Suite);
      Result.Add_Test (Improve_Verification_Test_Suite.Suite);
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
