with Ada.Strings.Unbounded;
with Ada_Quality.Coverage;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve_Coverage_Units;
with Project_Tools.Files;
with Project_Tools.Test_Fixtures;

package body Improve_Coverage_Units_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;

   type Coverage_Case is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Coverage_Case;

   overriding function Name (Item : Coverage_Case) return AUnit.Message_String is
     (AUnit.Format ("IMP_COVERAGE_SUBUNIT_RESOLUTION"));

   overriding procedure Run_Test (Item : in out Coverage_Case) is
      pragma Unreferenced (Item);
      Root : constant String := Project_Tools.Test_Fixtures.Fresh_Temp_Dir ("improve-coverage-units");

      procedure Write (Name, Text : String) is
      begin
         Project_Tools.Files.Write_Text_File (Project_Tools.Files.Join (Root, Name), Text);
      end Write;

      function Unit (Stem, Body_Name : String) return Ada_Quality.Coverage.Production_Unit is
        ((To_Unbounded_String (Stem), To_Unbounded_String (Project_Tools.Files.Join (Root, Body_Name)),
          Null_Unbounded_String));

      procedure Require_Failure
        (Value : Ada_Quality.Coverage.Production_Unit;
         Label : String) is
         Rejected : Boolean := False;
      begin
         begin
            declare Result : constant String := Improve_Coverage_Units.Compilation_Stem (Value); begin
               Rejected := Result = "";
            end;
         exception
            when Program_Error => Rejected := True;
         end;
         Assert (Rejected, Label);
      end Require_Failure;
   begin
      Write
        ("ordinary.adb",
         "procedure Ordinary is" & ASCII.LF &
         "   Text : constant String := ""separate (Fake.Parent)"";" & ASCII.LF &
         "begin" & ASCII.LF & "   null; -- separate (Ignored.Parent)" & ASCII.LF & "end Ordinary;" & ASCII.LF);
      Assert
        (Improve_Coverage_Units.Compilation_Stem (Unit ("ordinary", "ordinary.adb")) = "ordinary",
         "coverage parser treated comments or strings as a subunit declaration");

      Write ("root-parent.adb", "procedure Root.Parent is begin null; end Root.Parent;" & ASCII.LF);
      Write
        ("root-parent-child.adb",
         "-- context before the subunit" & ASCII.LF & "separate -- parent follows" & ASCII.LF &
         "  (Root.Parent)" & ASCII.LF & "procedure Child is begin null; end Child;" & ASCII.LF);
      Assert
        (Improve_Coverage_Units.Compilation_Stem
           (Unit ("root-parent-child", "root-parent-child.adb")) = "root-parent",
         "coverage parser did not resolve a commented subunit context clause");

      Write
        ("root-parent-nested.adb",
         "separate (Root.Parent) procedure Nested is begin null; end Nested;" & ASCII.LF);
      Write
        ("root-parent-nested-child.adb",
         "separate (Root.Parent.Nested) procedure Child is begin null; end Child;" & ASCII.LF);
      Assert
        (Improve_Coverage_Units.Compilation_Stem
           (Unit ("root-parent-nested-child", "root-parent-nested-child.adb")) = "root-parent",
         "coverage parser did not resolve nested subunits to their compilation body");

      Write ("malformed.adb", "separate (Root-Parent) procedure Broken is begin null; end Broken;" & ASCII.LF);
      Require_Failure (Unit ("malformed", "malformed.adb"), "malformed subunit parent was accepted");

      Write ("cycle-child.adb", "separate (Cycle_A) procedure Child is begin null; end Child;" & ASCII.LF);
      Write ("cycle_a.adb", "separate (Cycle_B) procedure Cycle_A is begin null; end Cycle_A;" & ASCII.LF);
      Write ("cycle_b.adb", "separate (Cycle_A) procedure Cycle_B is begin null; end Cycle_B;" & ASCII.LF);
      Require_Failure (Unit ("cycle-child", "cycle-child.adb"), "cyclic subunit parents were accepted");
      Project_Tools.Test_Fixtures.Cleanup (Root);
   exception
      when others =>
         Project_Tools.Test_Fixtures.Cleanup (Root);
         raise;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Case_Access'(new Coverage_Case));
      return Result;
   end Suite;
end Improve_Coverage_Units_Test_Suite;
