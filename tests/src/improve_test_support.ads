with Ada.Strings.Unbounded;
with Ada_Quality.Policy;
with Ada_Quality.Types;
with Improve.CLI;
with Improve.Model;

--  Shared integration fixtures kept independent from individual AUnit suites.
package Improve_Test_Support is
   function Args (Text : String) return Improve.CLI.String_Vectors.Vector;

   function Id_Image (Value : Positive) return String;

   procedure Must_Reject (Text, Expected : String);

   type Fixture is record
      Directory   : Ada.Strings.Unbounded.Unbounded_String;
      Database    : Ada.Strings.Unbounded.Unbounded_String;
      Project     : Positive;
      Run         : Positive;
      Interrupted : Positive;
      Target      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Build_Fixture
     (Label                     : String;
      Multiple_Structure        : Boolean := False;
      Second_Structure_Severity : Ada_Quality.Types.Severity := Ada_Quality.Types.High) return Fixture;

   function Add_Fixture_Project (Data : Fixture; Label : String) return Fixture;

   procedure Initialize_Harness (Directory : String);

   procedure Remove (Item : Fixture);

   function Publish_Real_Assessment
     (Database : String;
      Project  : Positive;
      Root     : String;
      Policy   : Ada_Quality.Policy.Quality_Policy) return Positive;

   type Followup_State is (All_Pass, Structure_Failing, Structure_Unmeasurable);

   function Publish_Followup
     (Data               : Fixture;
      Structure_State    : Followup_State := All_Pass;
      Policy             : String := "policy-a";
      Source             : String := "";
      Toolchain          : String := "gnat-15.2.1";
      Structure_Severity : Ada_Quality.Types.Severity := Ada_Quality.Types.High;
      New_Critical       : Boolean := False) return Positive;

   procedure Replace_Assessment_Source
     (Database_Path : String;
      Run_Id        : Positive;
      Source         : String);
   --  Corrupt one completed assessment source identity for integrity regression testing.

   function Prepare_Verification_Plan (Data : Fixture; State : String) return Improve.CLI.Outcome;

   procedure Approve_Latest (State : String);

   function Draft_For (Data : Fixture) return Improve.Model.Plan_Revision;
end Improve_Test_Support;
