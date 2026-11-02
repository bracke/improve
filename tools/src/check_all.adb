with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Project_Tools.Files;

--  Fast repository checks used before the deeper Ada Quality release gates exist.
procedure Check_All is
   use Ada.Strings.Unbounded;
   Failed : Boolean := False;

   procedure Check_File (Path : String) is
   begin
      if not Project_Tools.Files.File_Exists (Path) then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "missing required file: " & Path);
         Failed := True;
         return;
      end if;
      declare
         Text   : constant String := Project_Tools.Files.Read_Raw_File (Path);
         Column : Natural := 0;
      begin
         for C of Text loop
            if C = Character'Val (10) then
               Column := 0;
            else
               Column := Column + 1;
               if Column = 121 then
                  Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "line exceeds 120 columns: " & Path);
                  Failed := True;
               end if;
            end if;
            if C = Character'Val (9) then
               Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "tab character in source: " & Path);
               Failed := True;
            end if;
         end loop;
      end;
   end Check_File;

   procedure Reject_Non_Ada_Tooling (Pattern : String) is
   begin
      for Path of Project_Tools.Files.List_Tree ("tools", Pattern) loop
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "non-Ada repository tooling is prohibited: " & To_String (Path));
         Failed := True;
      end loop;
   end Reject_Non_Ada_Tooling;
begin
   for Path of Project_Tools.Files.List_Tree ("src", "*.ad?") loop Check_File (To_String (Path)); end loop;
   for Path of Project_Tools.Files.List_Tree ("tests/src", "*.ad?") loop Check_File (To_String (Path)); end loop;
   for Path of Project_Tools.Files.List_Tree ("tools/src", "*.ad?") loop Check_File (To_String (Path)); end loop;
   Check_File ("alire.toml");
   Check_File ("improve.gpr");
   Check_File ("improve_docs.gpr");
   Check_File ("improve_spark.gpr");
   Check_File ("tests/coverage.gpr");
   Check_File ("tools/improve_tools.gpr");
   Check_File ("README.md");
   Check_File ("LICENSE");
   Check_File ("config/improve.toml");
   Check_File ("docs/release-readiness.md");
   Reject_Non_Ada_Tooling ("*.sh");
   Reject_Non_Ada_Tooling ("*.py");
   if Failed then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Ada.Text_IO.Put_Line ("repository checks passed");
   end if;
end Check_All;

