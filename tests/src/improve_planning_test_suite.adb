with Ada.Directories;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve;
with Improve.Config;
with Improve.Model;
with Improve.Operations.Planning;
with Improve.Storage;
with Project_Tools.Files;

package body Improve_Planning_Test_Suite is
   use AUnit.Assertions;

   type Planning_Case is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Planning_Case;

   overriding procedure Run_Test (Item : in out Planning_Case);

   overriding function Name (Item : Planning_Case) return AUnit.Message_String is
     (AUnit.Format ("IMP_PLANNING_ERROR_BOUNDARIES"));

   overriding procedure Run_Test (Item : in out Planning_Case) is
      pragma Unreferenced (Item);
      Root    : constant String := "/tmp/improve_planning_error_boundaries";
      Missing : constant String := Root & "/missing.db";
      State   : constant String := Root & "/state.db";
      Rejected : Natural := 0;
   begin
      Project_Tools.Files.Delete_Tree (Root);
      Ada.Directories.Create_Directory (Root);
      begin
         declare
            Value : constant Improve.Operations.Planning.Generation_Result :=
              Improve.Operations.Planning.Generate
                (State, Missing, "1", 0, Improve.Config.Defaults, Dry_Run => True);
            pragma Unreferenced (Value);
         begin
            null;
         end;
      exception
         when Improve.Dependency_Error => Rejected := Rejected + 1;
      end;
      begin
         declare
            Value : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Load (Missing, "PLAN-000001");
            pragma Unreferenced (Value);
         begin
            null;
         end;
      exception
         when Improve.Dependency_Error => Rejected := Rejected + 1;
      end;
      begin
         declare
            Value : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Operations.Planning.List (State, Missing, "1");
            pragma Unreferenced (Value);
         begin
            null;
         end;
      exception
         when Improve.Dependency_Error => Rejected := Rejected + 1;
      end;
      begin
         declare
            Value : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Approve (State, "PLAN-000001");
            pragma Unreferenced (Value);
         begin
            null;
         end;
      exception
         when Improve.Argument_Error => Rejected := Rejected + 1;
      end;
      Assert (Rejected = 4, "planning operations did not preserve their typed failure boundaries");
      Project_Tools.Files.Delete_Tree (Root);
   exception
      when others =>
         Project_Tools.Files.Delete_Tree (Root);
         raise;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Case_Access'(new Planning_Case));
      return Result;
   end Suite;
end Improve_Planning_Test_Suite;
