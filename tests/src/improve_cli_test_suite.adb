with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Ada_Quality.Reporting;
with Improve.CLI;
with Improve.Config;
with Improve.Presentation;
with Improve.Recovery;
with Improve.Storage;
with Improve.Tasks;
with Improve.Verification;
with Improve.Workflow;
with Project_Tools.Files;

package body Improve_CLI_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Improve.CLI.Command_Kind;
   use type Improve.CLI.Plan_Operation;
   use type Improve.Config.Color_Mode;

   type Test_Id is
     (Parse_Plan, Reject_Duplicate, Reject_Conflict, Reject_Missing_Project, Reject_Command_Option,
      JSON_Disables_Color, Terminal_Text_Sanitized, Help_Smoke, Version_Smoke, Quiet_Smoke,
      Verbose_Smoke, Config_Smoke, Invalid_Smoke);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding procedure Run_Test (Item : in out Case_Test);

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_" & Test_Id'Image (Item.Id)));

   function Args (Text : String) return Improve.CLI.String_Vectors.Vector is
      Result : Improve.CLI.String_Vectors.Vector;
      Start  : Positive := Text'First;
   begin
      if Text = "" then
         return Result;
      end if;
      for Index in Text'Range loop
         if Text (Index) = '|' then
            Result.Append (Text (Start .. Index - 1));
            Start := Index + 1;
         end if;
      end loop;
      Result.Append (Text (Start .. Text'Last));
      return Result;
   end Args;

   procedure Must_Reject (Text, Expected : String) is
      Rejected : Boolean := False;
   begin
      begin
         declare
            Item : constant Improve.CLI.Invocation := Improve.CLI.Parse (Args (Text));
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

   overriding procedure Run_Test (Item : in out Case_Test) is
   begin
      case Item.Id is
         when Parse_Plan =>
            declare
               Parsed : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse
                   (Args ("--config|custom.toml|--database|q.db|plan|--project|demo|--run=42|--dry-run"));
            begin
               Assert
                 (Parsed.Command = Improve.CLI.Plan_Command and then
                  Parsed.Plan_Action = Improve.CLI.Create_Plan and then Parsed.Run_Id = 42 and then
                  Parsed.Dry_Run and then Parsed.Has_Config and then
                  To_String (Parsed.Config) = "custom.toml" and then To_String (Parsed.Project) = "demo",
                  "plan options were not parsed");
            end;
         when Reject_Duplicate =>
            Must_Reject ("projects|--format|json|--format|terminal", "more than once");
         when Reject_Conflict =>
            Must_Reject ("projects|--verbose|--quiet", "mutually exclusive");
         when Reject_Missing_Project =>
            Must_Reject ("findings", "requires --project");
         when Reject_Command_Option =>
            Must_Reject ("projects|--run|1", "not accepted");
         when JSON_Disables_Color =>
            declare
               Parsed : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse (Args ("projects|--format|json|--color|always"));
            begin
               Assert (Parsed.Color = Improve.Config.Color_Never, "JSON did not force color off");
            end;
         when Terminal_Text_Sanitized =>
            declare
               Unsafe : constant String := "before" & Character'Val (27) & "[2J" & ASCII.LF & "after";
               Safe   : constant String := Improve.Presentation.Safe_Text (Unsafe);
               Unicode_Unsafe : constant String :=
                 "left" & Character'Val (16#C2#) & Character'Val (16#9B#) &
                 Character'Val (16#E2#) & Character'Val (16#80#) & Character'Val (16#AE#) & "right";
               Unicode_Safe : constant String := Improve.Presentation.Safe_Text (Unicode_Unsafe);
               Invalid_UTF8_Safe : constant String :=
                 Improve.Presentation.Safe_Text ("raw" & Character'Val (16#9B#) & "control");
               Publications : constant Improve.Workflow.Publication_Result := (others => <>);
               Recovery     : constant Improve.Recovery.Recovery_Report :=
                 (Operations_Recovered => 1, Tasks_Recovered => 2);
               Verification : constant Improve.Verification.Report :=
                 (Plan_Id          => To_Unbounded_String ("PLAN-000001"),
                  Baseline_Run     => 1,
                  Verification_Run => 2,
                  others           => <>);
            begin
               Assert
                 (Ada.Strings.Fixed.Index (Safe, Character'Val (27) & "[2J") = 0 and then
                  Ada.Strings.Fixed.Index (Safe, ASCII.LF & "after") = 0,
                  "terminal sanitizer retained control characters");
               Assert
                 (Ada.Strings.Fixed.Index (Unicode_Safe, String'(1 => Character'Val (16#9B#))) = 0 and then
                  Ada.Strings.Fixed.Index (Unicode_Safe, String'(1 => Character'Val (16#AE#))) = 0,
                  "terminal sanitizer retained Unicode control characters");
               Assert
                 (Ada.Strings.Fixed.Index
                    (Invalid_UTF8_Safe, String'(1 => Character'Val (16#9B#))) = 0,
                  "terminal sanitizer retained an invalid encoded control byte");
               Assert
                 (Improve.Presentation.Projects (Ada_Quality.Reporting.Project_Vectors.Empty_Vector)'Length > 0
                  and then
                  Improve.Presentation.Plans (Improve.Storage.Summary_Vectors.Empty_Vector)'Length > 0 and then
                  Improve.Presentation.Tasks (Improve.Tasks.View_Vectors.Empty_Vector)'Length > 0 and then
                  Improve.Presentation.Status (Improve.Tasks.Status_Vectors.Empty_Vector) = "" and then
                  Improve.Presentation.Publication ("PLAN-000001", Publications, True)'Length > 0 and then
                  Improve.Presentation.Recovery (Recovery)'Length > 0 and then
                  Improve.Presentation.Verification ("PLAN-000001", Verification, "refresh")'Length > 0,
                  "terminal empty-state rendering failed");
            end;
         when Help_Smoke =>
            declare
               Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("help"));
            begin
               Assert
                 (Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index (To_String (Result.Output), "Usage:") > 0,
                  "help did not succeed");
            end;
         when Version_Smoke =>
            declare
               Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("version|--format|json"));
            begin
               Assert
                 (Result.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Result.Output), """schema_version"":1") > 0,
                  "JSON version output is not versioned");
            end;
         when Quiet_Smoke =>
            declare Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("version|--quiet")); begin
               Assert (Result.Exit_Code = 0 and then Length (Result.Output) = 0, "quiet output was not suppressed");
            end;
         when Verbose_Smoke =>
            declare Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("version|--verbose")); begin
               Assert
                 (Result.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Result.Output), "command version") > 0,
                  "verbose output omitted operational context");
            end;
         when Config_Smoke =>
            declare
               Config_Path : constant String :=
                 (if Project_Tools.Files.File_Exists ("config/improve.toml")
                  then "config/improve.toml" else "../config/improve.toml");
               Result : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("config|validate|--config|" & Config_Path));
               Missing : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("config|validate|--config|missing-improve-config.toml"));
            begin
               Assert
                 (Result.Exit_Code = 0 and then Missing.Exit_Code = Improve.CLI.Argument_Exit,
                  "configuration validation did not honor its explicit source");
            end;
         when Invalid_Smoke =>
            declare
               Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("unknown"));
            begin
               Assert
                 (Result.Exit_Code = 2 and then Length (Result.Output) = 0 and then Length (Result.Errors) > 0,
                  "invalid command did not observe the output contract");
            end;
      end case;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      for Id in Test_Id loop
         Result.Add_Test (Case_Access'(new Case_Test (Id)));
      end loop;
      return Result;
   end Suite;
end Improve_CLI_Test_Suite;
