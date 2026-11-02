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
with Improve.Findings;
with Improve.Model;
with Improve.Source;
with Improve.Text;
with Project_Tools.Files;

package body Improve_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Improve.CLI.Command_Kind;
   use type Improve.CLI.Plan_Operation;
   use type Improve.Config.Color_Mode;
   use type Ada.Containers.Count_Type;

   type Test_Id is
     (Parse_Plan, Reject_Duplicate, Reject_Conflict, Reject_Missing_Project, Reject_Command_Option,
      JSON_Disables_Color, Help_Smoke, Version_Smoke, Config_Smoke, Invalid_Smoke, Catalog, Digest,
      Project_Discovery, Latest_Completed, Explicit_Incomplete_Rejected, Normalize_Findings,
      Unknown_Project_Rejected, Safe_Path_Validation, Projects_CLI, Findings_CLI);

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
   end record;

   function Build_Fixture (Label : String) return Fixture is
      use Ada_Quality.Types;
      Directory : constant String := "/tmp/improve_phase2_" & Label;
      DB_Path   : constant String := Directory & "/quality.db";
      Store     : Ada_Quality.Storage.Store;
      Project   : Positive;
      Run       : Positive;
      Later     : Positive;
      Value     : Assessment;
   begin
      Project_Tools.Files.Delete_Tree (Directory);
      Ada.Directories.Create_Directory (Directory);
      Ada_Quality.Storage.Open (Store, DB_Path);
      Project := Ada_Quality.Storage.Add_Project (Store, Ada.Directories.Full_Name (".."));
      Run := Ada_Quality.Storage.Start_Assessment (Store, Project, "source-a", "policy-a");
      Value.Id := Run;
      Value.Project_Id := Project;
      Value.Project_Path := To_Unbounded_String (Ada.Directories.Full_Name (".."));
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
        (To_Unbounded_String (Directory), To_Unbounded_String (DB_Path), Project, Run, Later);
   end Build_Fixture;

   procedure Remove (Item : Fixture) is
   begin
      Project_Tools.Files.Delete_Tree (To_String (Item.Directory));
   end Remove;

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
