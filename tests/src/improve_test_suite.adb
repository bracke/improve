with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Exceptions;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve;
with Improve.CLI;
with Improve.Config;
with Improve.Text;

package body Improve_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Improve.CLI.Command_Kind;
   use type Improve.CLI.Plan_Operation;
   use type Improve.Config.Color_Mode;

   type Test_Id is
     (Parse_Plan, Reject_Duplicate, Reject_Conflict, Reject_Missing_Project, Reject_Command_Option,
      JSON_Disables_Color, Help_Smoke, Version_Smoke, Config_Smoke, Invalid_Smoke, Catalog, Digest);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding function Name (Item : Case_Test) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Case_Test);

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_P1_" & Test_Id'Image (Item.Id)));

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
