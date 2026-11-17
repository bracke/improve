with Ada.Strings.Unbounded;
with Ada_Quality.Coverage;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve_Coverage_Units;

package body Improve_Coverage_Units_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;

   type Coverage_Case is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Coverage_Case;

   overriding function Name (Item : Coverage_Case) return AUnit.Message_String is
     (AUnit.Format ("IMP_COVERAGE_SUBUNIT_RESOLUTION"));

   overriding procedure Run_Test (Item : in out Coverage_Case) is
      pragma Unreferenced (Item);

      function Unit (Stem : String) return Ada_Quality.Coverage.Production_Unit is
        ((Stem          => To_Unbounded_String (Stem),
          Body_Path     => Null_Unbounded_String,
          Spec_Path     => Null_Unbounded_String,
          Subunit_Paths => <>));

      procedure Add_Subunit
        (Owner : in out Ada_Quality.Coverage.Production_Unit;
         Path  : String) is
      begin
         Owner.Subunit_Paths.Append (To_Unbounded_String (Path));
      end Add_Subunit;

      procedure Require_Failure
        (Value : Ada_Quality.Coverage.Production_Unit;
         Units : Ada_Quality.Coverage.Production_Unit_Vectors.Vector;
         Label : String) is
         Rejected : Boolean := False;
      begin
         begin
            declare
               Result : constant String := Improve_Coverage_Units.Compilation_Stem (Value, Units);
               pragma Unreferenced (Result);
            begin
               null;
            end;
         exception
            when Program_Error => Rejected := True;
         end;
         Assert (Rejected, Label);
      end Require_Failure;

      Root   : Ada_Quality.Coverage.Production_Unit := Unit ("root-parent");
      Nested : Ada_Quality.Coverage.Production_Unit := Unit ("root-parent-nested");
      Leaf   : constant Ada_Quality.Coverage.Production_Unit := Unit ("ordinary");
      Units  : Ada_Quality.Coverage.Production_Unit_Vectors.Vector;
   begin
      Add_Subunit (Root, "/source/root-parent-nested.adb");
      Add_Subunit (Nested, "/source/root-parent-nested-child.adb");
      Units.Append (Root);
      Units.Append (Nested);
      Units.Append (Leaf);
      Assert
        (Improve_Coverage_Units.Compilation_Stem (Leaf, Units) = "ordinary",
         "coverage inventory changed an ordinary compilation stem");
      Assert
        (Improve_Coverage_Units.Compilation_Stem (Nested, Units) = "root-parent",
         "coverage inventory did not resolve nested subunit ownership");

      declare
         Left      : Ada_Quality.Coverage.Production_Unit := Unit ("left");
         Right     : Ada_Quality.Coverage.Production_Unit := Unit ("right");
         Child     : constant Ada_Quality.Coverage.Production_Unit := Unit ("shared-child");
         Ambiguous : Ada_Quality.Coverage.Production_Unit_Vectors.Vector;
      begin
         Add_Subunit (Left, "/left/shared-child.adb");
         Add_Subunit (Right, "/right/shared-child.adb");
         Ambiguous.Append (Left);
         Ambiguous.Append (Right);
         Ambiguous.Append (Child);
         Require_Failure (Child, Ambiguous, "ambiguous typed subunit ownership was accepted");
      end;

      declare
         Left  : Ada_Quality.Coverage.Production_Unit := Unit ("cycle-left");
         Right : Ada_Quality.Coverage.Production_Unit := Unit ("cycle-right");
         Cycle : Ada_Quality.Coverage.Production_Unit_Vectors.Vector;
      begin
         Add_Subunit (Left, "/cycle/cycle-right.adb");
         Add_Subunit (Right, "/cycle/cycle-left.adb");
         Cycle.Append (Left);
         Cycle.Append (Right);
         Require_Failure (Left, Cycle, "cyclic typed subunit ownership was accepted");
      end;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Case_Access'(new Coverage_Case));
      return Result;
   end Suite;
end Improve_Coverage_Units_Test_Suite;
