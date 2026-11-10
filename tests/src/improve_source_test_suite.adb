with Ada.Directories;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve.Source;
with Project_Tools.Files;

package body Improve_Source_Test_Suite is
   use AUnit.Assertions;

   type Test_Id is (Fingerprint_Deterministic, Fingerprint_Boundary_Safe);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding procedure Run_Test (Item : in out Case_Test);

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_SOURCE_" & Test_Id'Image (Item.Id)));

   overriding procedure Run_Test (Item : in out Case_Test) is
      Root : constant String := "/tmp/improve_source_" & Test_Id'Image (Item.Id);
   begin
      Project_Tools.Files.Delete_Tree (Root);
      Ada.Directories.Create_Directory (Root);
      case Item.Id is
         when Fingerprint_Deterministic =>
            Project_Tools.Files.Write_Raw_File (Root & "/a", "alpha");
            declare
               First  : constant String := Improve.Source.Working_Fingerprint (Root);
               Second : constant String := Improve.Source.Working_Fingerprint (Root);
            begin
               Assert (First = Second, "unchanged source inventory produced different fingerprints");
               Assert
                 (First'Length = 82 and then First (First'First .. First'First + 17) = "working-sha256-v2:",
                  "working-source fingerprint is not the versioned SHA-256 format");
            end;
         when Fingerprint_Boundary_Safe =>
            Project_Tools.Files.Write_Raw_File (Root & "/a", "x");
            Project_Tools.Files.Write_Raw_File (Root & "/b", "y");
            declare
               Two_Files : constant String := Improve.Source.Working_Fingerprint (Root);
            begin
               Project_Tools.Files.Delete_Tree (Root);
               Ada.Directories.Create_Directory (Root);
               Project_Tools.Files.Write_Raw_File (Root & "/a", "xb" & Character'Val (0) & "y");
               Assert
                 (Two_Files /= Improve.Source.Working_Fingerprint (Root),
                  "different source inventories collided at a path/content boundary");
            end;
      end case;
      Project_Tools.Files.Delete_Tree (Root);
   exception
      when others =>
         Project_Tools.Files.Delete_Tree (Root);
         raise;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      for Id in Test_Id loop
         Result.Add_Test (Case_Access'(new Case_Test (Id)));
      end loop;
      return Result;
   end Suite;
end Improve_Source_Test_Suite;
