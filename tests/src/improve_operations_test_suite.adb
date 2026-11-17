with Ada.Directories;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
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
with Improve.Model;
with Improve.Operations;
with Improve.Operations.Inspection;
with Improve.Planner;
with Improve.Recovery;
with Improve.Refinement;
with Improve.State;
with Improve.Storage;
with Improve.Tasks;
with Improve.Verification;
with Improve.Workflow;
with Hostkit.Fs;
with Improve_Test_Support;
with Model_Runner.Errors;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;
with Project_Tools.Files;

package body Improve_Operations_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Improve_Test_Support;
   use type Improve.Config.Color_Mode;
   use type Improve.Config.Output_Format;
   use type Improve.Config.Severity_Level;
   use type Improve.Config.Evidence_Limits;
   use type Improve.Tasks.Verification_Freshness;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Types.Indicator_Id;

   type Test_Id is
     (In_Project_State_Does_Not_Stale_Plan, Tasks_CLI_Golden, Tasks_JSON_Filter,
      Status_Project_And_All, Status_Verification_Freshness,
      Status_All_Mixed_Freshness, Interrupted_Publication_Recovery, Recovery_Rejects_Stale_Uncommitted,
      Recovery_Rejects_Policy_Change, Published_Task_Reused_Across_Revisions,
      Recovery_Uses_Exact_Revision, Recovery_Limit_Enforced,
      Recover_Missing_State, Configuration_Bounds, Operational_Terminal_Paths, Real_End_To_End_Workflow);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding procedure Run_Test (Item : in out Case_Test);

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_OPERATIONS_" & Test_Id'Image (Item.Id)));

   procedure Run_Inspection_Test (Item : in out Case_Test) is separate;
   procedure Run_Recovery_Test (Item : in out Case_Test) is separate;
   procedure Run_Operations_Test (Item : in out Case_Test) is separate;

   overriding procedure Run_Test (Item : in out Case_Test) is
   begin
      case Item.Id is
         when In_Project_State_Does_Not_Stale_Plan .. Status_All_Mixed_Freshness =>
            Run_Inspection_Test (Item);
         when Interrupted_Publication_Recovery .. Recover_Missing_State =>
            Run_Recovery_Test (Item);
         when Configuration_Bounds .. Real_End_To_End_Workflow =>
            Run_Operations_Test (Item);
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
end Improve_Operations_Test_Suite;
