with Ada.Exceptions;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve;
with Improve.CLI;
with Improve.Model;
with Improve.Operations;
with Improve.State;
with Improve.Storage;
with Improve.Workflow;
with Improve_Test_Support;
with Model_Runner.Errors;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Schemas;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;

package body Improve_Publication_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Improve_Test_Support;
   use type Ada.Containers.Count_Type;

   type Test_Id is
     (Native_Publication_And_Recovery, Publication_Namespace_Isolated,
      Native_Task_Contract_Fidelity, Changed_Task_Contract_Replaced,
      Replacement_Running_And_Completed, Workspace_Lifecycle_Fails_Closed,
      Selective_Publication_Resolves_Dependency, Prerequisite_Replacement_Migrates_Dependents,
      Refresh_Reconciles_State, Refresh_Rejects_Definition_Drift);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding procedure Run_Test (Item : in out Case_Test);

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_PUBLICATION_" & Test_Id'Image (Item.Id)));

   procedure Run_Core_Test (Item : in out Case_Test) is separate;
   procedure Run_Lifecycle_Test (Item : in out Case_Test) is separate;
   procedure Run_Dependencies_Test (Item : in out Case_Test) is separate;
   procedure Run_Refresh_Test (Item : in out Case_Test) is separate;

   overriding procedure Run_Test (Item : in out Case_Test) is
   begin
      case Item.Id is
         when Native_Publication_And_Recovery .. Changed_Task_Contract_Replaced =>
            Run_Core_Test (Item);
         when Replacement_Running_And_Completed .. Workspace_Lifecycle_Fails_Closed =>
            Run_Lifecycle_Test (Item);
         when Selective_Publication_Resolves_Dependency .. Prerequisite_Replacement_Migrates_Dependents =>
            Run_Dependencies_Test (Item);
         when Refresh_Reconciles_State | Refresh_Rejects_Definition_Drift =>
            Run_Refresh_Test (Item);
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
end Improve_Publication_Test_Suite;
