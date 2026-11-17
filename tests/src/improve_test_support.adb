with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada_Quality.Checks;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Storage;
with AUnit.Assertions;
with Database;
with Database.Catalog;
with Database.Predicates;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Values;
with Improve.Config;
with Improve.Findings;
with Improve.Operations;
with Improve.Planner;
with Improve.Source;
with Hostkit.Fs;
with Model_Runner.Errors;
with Model_Runner.Framework.Configuration_Records;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Schemas;
with Model_Runner.Framework.Stores;
with Project_Tools.Files;

package body Improve_Test_Support is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use AUnit.Assertions;
   use type Ada_Quality.Types.Indicator_Id;

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

   function Finding_Fingerprint
     (Indicator : Ada_Quality.Types.Indicator_Id;
      Rule, Path, Message : String) return String is
     (Ada_Quality.Finding_Identity.Create (Indicator, Rule, Path, Message));

   function Assessment_Fixture
     (Run, Project : Positive;
      Target, Source, Policy, Toolchain, Evidence_Prefix : String)
      return Ada_Quality.Types.Assessment is
      use Ada_Quality.Types;
      Result : Assessment;
   begin
      Result.Id := Run;
      Result.Project_Id := Project;
      Result.Project_Path := To_Unbounded_String (Target);
      Result.Source_Fingerprint := To_Unbounded_String (Source);
      Result.Policy_Fingerprint := To_Unbounded_String (Policy);
      Result.Toolchain_Fingerprint := To_Unbounded_String (Toolchain);
      Result.Status := Assessment_Completed;
      for Indicator in Indicator_Id loop
         Result.Results.Append
           (Indicator_Result'
              (Indicator   => Indicator,
               Execution   => Succeeded,
               Compliance  => Pass,
               Applicable  => True,
               Summary     => To_Unbounded_String ("pass"),
               Evidence    => To_Unbounded_String (Evidence_Prefix & Image (Indicator)),
               Measurement => (Kind => Boolean_Value, Boolean_Data => True),
               Findings    => <>));
      end loop;
      return Result;
   end Assessment_Fixture;

   procedure Set_Result
     (Value       : in out Ada_Quality.Types.Assessment;
      Indicator   : Ada_Quality.Types.Indicator_Id;
      Execution   : Ada_Quality.Types.Execution_Status;
      Compliance  : Ada_Quality.Types.Compliance_Status;
      Summary     : String;
      Measurement : Ada_Quality.Types.Measurement_Value) is
      Index : constant Positive := Value.Results.First_Index + Ada_Quality.Types.Indicator_Id'Pos (Indicator);
      Item  : Ada_Quality.Types.Indicator_Result := Value.Results (Index);
   begin
      if Item.Indicator /= Indicator then
         raise Program_Error with "assessment fixture indicator order is inconsistent";
      end if;
      Item.Execution := Execution;
      Item.Compliance := Compliance;
      Item.Summary := To_Unbounded_String (Summary);
      Item.Measurement := Measurement;
      Value.Results.Replace_Element (Index, Item);
   end Set_Result;

   procedure Add_Finding
     (Value     : in out Ada_Quality.Types.Assessment;
      Indicator : Ada_Quality.Types.Indicator_Id;
      Rule       : String;
      Level      : Ada_Quality.Types.Severity;
      Message    : String;
      Path       : String;
      Line       : Natural) is
      Index : constant Positive := Value.Results.First_Index + Ada_Quality.Types.Indicator_Id'Pos (Indicator);
      Item  : Ada_Quality.Types.Indicator_Result := Value.Results (Index);
   begin
      if Item.Indicator /= Indicator then
         raise Program_Error with "assessment fixture indicator order is inconsistent";
      end if;
      Item.Findings.Append
        (Ada_Quality.Types.Finding'
           (Indicator     => Indicator,
            Rule          => To_Unbounded_String (Rule),
            Level         => Level,
            Message       => To_Unbounded_String (Message),
            Relative_Path => To_Unbounded_String (Path),
            Line          => Line,
            Fingerprint   => To_Unbounded_String
              (Finding_Fingerprint (Indicator, Rule, Path, Message))));
      Value.Results.Replace_Element (Index, Item);
   end Add_Finding;

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
      Directory : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-phase2-" & Label);
      DB_Path   : constant String := Directory & "/quality.db";
      Store     : Ada_Quality.Storage.Store;
      Project   : Positive;
      Run       : Positive;
      Later     : Positive;
      Value     : Assessment;
      Target    : constant String := Directory & "/project";
   begin
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
         Value := Assessment_Fixture
           (Run, Project, Target, Source, "policy-a", "gnat-15.2.1", "fixture evidence for ");
      end;
      Set_Result
        (Value, STR_01, Succeeded, Violation, "violation",
         (Kind => Boolean_Value, Boolean_Data => False));
      Set_Result
        (Value, TST_03, Succeeded, Violation, "violation",
         (Kind => Decimal_Value, Basis_Points => 8_200));
      Add_Finding
        (Value, STR_01, "manifest.invalid", High, "manifest is invalid", "alire.toml", 1);
      if Multiple_Structure then
         Add_Finding
           (Value, STR_01, "manifest.invalid", Second_Structure_Severity,
            "manifest has a second invalid field", "alire.toml", 2);
      end if;
      Set_Result
        (Value, BLD_04, Blocked, Unknown, "toolchain unavailable",
         (Kind => Unavailable_Value, Reason => To_Unbounded_String ("toolchain probe unavailable")));
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
         Value := Assessment_Fixture
           (Run, Project, Target, Source, "policy-a", "gnat-15.2.1", "fixture evidence for ");
      end;
      Set_Result
        (Value, STR_01, Succeeded, Violation, "violation",
         (Kind => Boolean_Value, Boolean_Data => False));
      Add_Finding
        (Value, STR_01, "manifest.invalid", High, "manifest is invalid", "alire.toml", 1);
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
      Value := Assessment_Fixture
        (Run, Data.Project, To_String (Data.Target), Effective_Source, Policy, Toolchain,
         "follow-up evidence for ");
      case Structure_State is
         when All_Pass =>
            null;
         when Structure_Failing =>
            Set_Result
              (Value, STR_01, Succeeded, Violation, "violation",
               (Kind => Boolean_Value, Boolean_Data => False));
            Add_Finding
              (Value, STR_01, "manifest.invalid", Structure_Severity,
               "manifest is invalid", "alire.toml", 1);
         when Structure_Unmeasurable =>
            Set_Result
              (Value, STR_01, Blocked, Unknown, "measurement unavailable",
               (Kind => Unavailable_Value, Reason => To_Unbounded_String ("fixture evidence unavailable")));
      end case;
      if New_Critical then
         Set_Result
           (Value, SEC_01, Succeeded, Violation, "new critical security violation",
            (Kind => Boolean_Value, Boolean_Data => False));
         Add_Finding
           (Value, SEC_01, "security.new-critical", Critical,
            "unrelated critical finding", "src/new_issue.adb", 1);
      end if;
      Run := Ada_Quality.Storage.Publish (Store, Value);
      Ada_Quality.Storage.Close (Store);
      return Run;
   end Publish_Followup;

   procedure Replace_Assessment_Evidence
     (Database_Path : String;
      Run_Id        : Positive) is
      type Quality_Entity is record
         Id        : Positive;
         Parent_Id : Natural := 0;
         Kind      : Unbounded_Wide_Wide_String;
         State     : Unbounded_Wide_Wide_String;
         Payload   : Unbounded_Wide_Wide_String;
         Active    : Boolean := True;
      end record;

      function To_Row (Value : Quality_Entity) return Database.Rows.Row is
         Result : Database.Rows.Row;
      begin
         Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Value.Id)));
         Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Value.Parent_Id)));
         Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Value.Kind)));
         Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Value.State)));
         Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Value.Payload)));
         Database.Rows.Append (Result, Database.Values.From_Boolean (Value.Active));
         return Result;
      end To_Row;

      function From_Row (Row : Database.Rows.Row) return Quality_Entity is
        ((Id        => Positive (Database.Rows.Get (Row, 0).Int),
          Parent_Id => Natural (Database.Rows.Get (Row, 1).Int),
          Kind      => Database.Rows.Get (Row, 2).Text,
          State     => Database.Rows.Get (Row, 3).Text,
          Payload   => Database.Rows.Get (Row, 4).Text,
          Active    => Database.Rows.Get (Row, 5).Bool));

      function Key_Of (Value : Quality_Entity) return Positive is (Value.Id);
      function Key_Value (Key : Positive) return Database.Values.Value is
        (Database.Values.From_Integer (Integer (Key)));

      package Quality_Tables is new Database.Tables.Typed
        (Quality_Entity, Positive, To_Row, From_Row, Key_Of, Key_Value);

      function Replace_Summary (Payload : String) return String is
         Prefix : constant String := "summary=";
         First  : constant Natural := Ada.Strings.Fixed.Index (Payload, Prefix);
         Last   : Natural := First + Prefix'Length;
      begin
         if First = 0 then
            raise Program_Error with "indicator fixture has no summary";
         end if;
         while Last <= Payload'Last and then Payload (Last) /= ASCII.LF loop
            Last := Last + 1;
         end loop;
         return Payload (Payload'First .. First + Prefix'Length - 1) &
           "mutated assessment evidence" &
           (if Last <= Payload'Last then Payload (Last .. Payload'Last) else "");
      end Replace_Summary;

      DB        : Database.Handle;
      Tx        : Database.Transactions.Transaction;
      Schema    : Database.Schema.Table_Schema;
      Cursor    : Quality_Tables.Cursor;
      Row       : Quality_Entity;
      Status    : Database.Status.Result;
      Predicate : constant Database.Predicates.Predicate :=
        Database.Predicates.Column_Equals
          (1, Database.Values.From_Integer (Integer (Run_Id)));
   begin
      Database.Open
        (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Database_Path));
      Assert (Database.Last_Operation_Succeeded (DB), "quality database could not be opened for evidence fixture");
      Status := Database.Catalog.Find_By_Name
        (Database.Catalog_State_Key (DB), "indicator_results", Schema);
      Assert (Database.Status.Is_Ok (Status), "indicator schema is unavailable for evidence fixture");
      Database.Transactions.Begin_Write (DB, Tx);
      Assert
        (Database.Status.Is_Ok (Database.Transactions.Result (Tx)),
         "assessment evidence mutation transaction could not be started");
      Status := Quality_Tables.Scan (Tx, DB, Schema, Predicate, Cursor);
      Assert
        (Database.Status.Is_Ok (Status) and then Quality_Tables.Has_Element (Cursor),
         "indicator result is unavailable for evidence fixture");
      Row := Quality_Tables.Element (Cursor);
      Row.Payload := To_Unbounded_Wide_Wide_String
        (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode
           (Replace_Summary
              (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
                 (To_Wide_Wide_String (Row.Payload)))));
      Assert
        (Database.Status.Is_Ok (Quality_Tables.Update (Tx, DB, Schema, Row)),
         "assessment evidence could not be mutated");
      Assert
        (Database.Status.Is_Ok (Database.Transactions.Commit (Tx)),
         "assessment evidence mutation could not be committed");
      Database.Close (DB);
      Assert
        (Database.Last_Operation_Succeeded (DB),
         "quality database could not be closed after evidence mutation");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Assert
              (Database.Status.Is_Ok (Database.Transactions.Rollback (Tx)),
               "assessment evidence mutation could not be rolled back");
         end if;
         if Database.Is_Open (DB) then
            Database.Close (DB);
            Assert
              (Database.Last_Operation_Succeeded (DB),
               "quality database could not be closed after evidence mutation failure");
         end if;
         raise;
   end Replace_Assessment_Evidence;

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
         Result   : constant Improve.Model.Plan_Revision :=
           Improve.Planner.Generate
             (Selected, Findings, Improve.Operations.Planning_Policy (Settings));
      begin
         Improve.Source.Close (Quality);
         return Result;
      end;
   end Draft_For;
end Improve_Test_Support;
