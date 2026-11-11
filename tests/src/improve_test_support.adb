with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada_Quality.Checks;
with Ada_Quality.Storage;
with AUnit.Assertions;
with Improve.Config;
with Improve.Findings;
with Improve.Planner;
with Improve.Source;
with Model_Runner.Errors;
with Model_Runner.Framework.Configuration_Records;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Schemas;
with Model_Runner.Framework.Stores;
with Project_Tools.Files;

package body Improve_Test_Support is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;

   function Args (Text : String) return Improve.CLI.String_Vectors.Vector is
      Result : Improve.CLI.String_Vectors.Vector;
      Start  : Positive := Text'First;
   begin
      if Text = "" then return Result; end if;
      for Index in Text'Range loop
         if Text (Index) = '|' then
            Result.Append (Text (Start .. Index - 1));
            Start := Index + 1;
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
         begin
            null;
         end;
      exception
         when Error : Improve.Argument_Error =>
            Rejected := Ada.Strings.Fixed.Index (Ada.Exceptions.Exception_Message (Error), Expected) > 0;
      end;
      Assert (Rejected, "expected rejection containing '" & Expected & "'");
   end Must_Reject;

   function Build_Fixture
     (Label                     : String;
      Multiple_Structure        : Boolean := False;
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
           (Indicator     => STR_01,
            Rule          => To_Unbounded_String ("manifest.invalid"),
            Level         => High,
            Message       => To_Unbounded_String ("manifest is invalid"),
            Relative_Path => To_Unbounded_String ("alire.toml"),
            Line          => 1,
            Fingerprint   => To_Unbounded_String ("fixture-manifest"));
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
        (Directory => Data.Directory, Database => Data.Database, Project => Project, Run => Run,
         Interrupted => Later, Target => To_Unbounded_String (Target));
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

   function Publish_Followup
     (Data               : Fixture;
      Structure_State    : Followup_State := All_Pass;
      Policy             : String := "policy-a";
      Source             : String := "";
      Toolchain          : String := "gnat-15.2.1";
      Structure_Severity : Ada_Quality.Types.Severity := Ada_Quality.Types.High;
      New_Critical       : Boolean := False) return Positive is
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
                  then "measurement unavailable" else "pass"),
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
end Improve_Test_Support;
