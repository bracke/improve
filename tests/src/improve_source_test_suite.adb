with Ada.Directories;
with Ada.Strings.Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Hostkit.Fs;
with Improve.Source;
with Project_Tools.Files;

package body Improve_Source_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Hostkit.Fs.Delete_Tree_Outcome;

   type Test_Id is
     (Fingerprint_Deterministic, Fingerprint_Boundary_Safe, Authored_Paths_Tracked,
      Generated_State_Ignored, Symlink_Rejected, Deep_Tree_Rejected, Oversized_File_Rejected,
      Quality_Database_Size_Rejected);

   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding procedure Run_Test (Item : in out Case_Test);

   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_SOURCE_" & Test_Id'Image (Item.Id)));

   overriding procedure Run_Test (Item : in out Case_Test) is
      Root : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-source");

      procedure Clear_Root is
         Outcome : constant Hostkit.Fs.Delete_Tree_Outcome := Hostkit.Fs.Delete_Tree_No_Follow (Root);
      begin
         if Ada.Directories.Exists (Root) and then Outcome = Hostkit.Fs.Tree_Delete_Failed then
            raise Program_Error with "test source fixture could not be removed";
         end if;
      end Clear_Root;
   begin
      Clear_Root;
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
                 (First'Length = 82 and then First (First'First .. First'First + 17) = "working-sha256-v4:",
                  "working-source fingerprint is not the versioned SHA-256 format");
            end;
         when Fingerprint_Boundary_Safe =>
            Project_Tools.Files.Write_Raw_File (Root & "/a", "x");
            Project_Tools.Files.Write_Raw_File (Root & "/b", "y");
            declare
               Two_Files : constant String := Improve.Source.Working_Fingerprint (Root);
            begin
               Clear_Root;
               Ada.Directories.Create_Directory (Root);
               Project_Tools.Files.Write_Raw_File (Root & "/a", "xb" & Character'Val (0) & "y");
               Assert
                 (Two_Files /= Improve.Source.Working_Fingerprint (Root),
                  "different source inventories collided at a path/content boundary");
            end;
         when Authored_Paths_Tracked =>
            Ada.Directories.Create_Directory (Root & "/lib");
            Ada.Directories.Create_Directory (Root & "/lib/bin");
            Project_Tools.Files.Write_Raw_File (Root & "/lib/unit.adb", "first");
            Project_Tools.Files.Write_Raw_File (Root & "/lib/bin/driver.adb", "first");
            Project_Tools.Files.Write_Raw_File (Root & "/fixture.db", "first");
            declare Initial : constant String := Improve.Source.Working_Fingerprint (Root); begin
               Project_Tools.Files.Write_Raw_File (Root & "/lib/unit.adb", "second");
               Assert
                 (Initial /= Improve.Source.Working_Fingerprint (Root),
                  "authored source below lib was excluded from the fingerprint");
               declare After_Library : constant String := Improve.Source.Working_Fingerprint (Root); begin
                  Project_Tools.Files.Write_Raw_File (Root & "/lib/bin/driver.adb", "second");
                  Assert
                    (After_Library /= Improve.Source.Working_Fingerprint (Root),
                     "authored nested directory sharing a generated basename was excluded");
               end;
               declare After_Nested : constant String := Improve.Source.Working_Fingerprint (Root); begin
                  Project_Tools.Files.Write_Raw_File (Root & "/fixture.db", "second");
                  Assert
                    (After_Nested /= Improve.Source.Working_Fingerprint (Root),
                     "authored database fixture was excluded from the fingerprint");
               end;
            end;
         when Generated_State_Ignored =>
            Project_Tools.Files.Write_Raw_File (Root & "/source.adb", "source");
            Ada.Directories.Create_Directory (Root & "/state");
            declare
               State   : constant String := Root & "/state/custom.db";
               Initial : constant String := Improve.Source.Working_Fingerprint (Root, State);
            begin
               Ada.Directories.Create_Directory (Root & "/obj");
               Project_Tools.Files.Write_Raw_File (Root & "/obj/generated.o", "generated");
               Project_Tools.Files.Write_Raw_File (Root & "/.improve.db", "state");
               Project_Tools.Files.Write_Raw_File (State, "custom state");
               Project_Tools.Files.Write_Raw_File (State & "-wal", "custom journal");
               Assert
                 (Initial = Improve.Source.Working_Fingerprint (Root, State),
                  "configured generated state changed the source fingerprint");
            end;
         when Symlink_Rejected =>
            declare
               Target   : constant String := Root & "_outside";
               Rejected : Boolean := False;
            begin
               Project_Tools.Files.Write_Raw_File (Target, "outside");
               if Hostkit.Fs.Create_Link (Target, Root & "/linked") then
                  begin
                     declare Value : constant String := Improve.Source.Working_Fingerprint (Root); begin
                        Assert (Value = "", "unsafe linked source unexpectedly produced a fingerprint");
                     end;
                  exception
                     when Improve.Data_Error => Rejected := True;
                  end;
                  Assert (Rejected, "symbolic link was followed while fingerprinting");
               end if;
               Project_Tools.Files.Delete_File_If_Present (Target);
            end;
         when Deep_Tree_Rejected =>
            declare
               Current  : Unbounded_String := To_Unbounded_String (Root);
               Rejected : Boolean := False;
            begin
               for Depth in 1 .. 129 loop
                  Append (Current, "/d");
                  Ada.Directories.Create_Directory (To_String (Current));
               end loop;
               begin
                  declare Value : constant String := Improve.Source.Working_Fingerprint (Root); begin
                     Assert (Value = "", "over-deep source tree unexpectedly produced a fingerprint");
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "over-deep source tree was not rejected");
            end;
         when Oversized_File_Rejected =>
            declare
               Rejected : Boolean := False;
            begin
               Project_Tools.Files.Write_Raw_File (Root & "/oversized.bin", "ab");
               begin
                  declare Value : constant String := Improve.Source.Working_Fingerprint
                    (Root, Maximum_File_Bytes => 1, Maximum_Total_Bytes => 2);
                  begin
                     Assert (Value = "", "oversized source unexpectedly produced a fingerprint");
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "configured per-file source limit was not enforced");
               Project_Tools.Files.Write_Raw_File (Root & "/oversized.bin", "a");
               Project_Tools.Files.Write_Raw_File (Root & "/second.bin", "b");
               Rejected := False;
               begin
                  declare Value : constant String := Improve.Source.Working_Fingerprint
                    (Root, Maximum_File_Bytes => 1, Maximum_Total_Bytes => 1);
                  begin
                     Assert (Value = "", "oversized source inventory unexpectedly produced a fingerprint");
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "configured total source limit was not enforced");
            end;
         when Quality_Database_Size_Rejected =>
            declare
               Repository : Improve.Source.Repository;
               Rejected   : Boolean := False;
               Path       : constant String := Root & "/quality.db";
            begin
               Project_Tools.Files.Write_Raw_File (Path, "oversized");
               begin
                  Improve.Source.Open
                    (Repository, Path, Maximum_Database_Bytes => 1);
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "oversized quality database reached the reporting loader");
            end;
      end case;
      Clear_Root;
   exception
      when others =>
         Clear_Root;
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
