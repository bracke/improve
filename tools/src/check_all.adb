with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Project_Tools.Alire_Manifests;
with Project_Tools.Files;
with Project_Tools.Release_Checks;

--  Fast repository checks used before the deeper Ada Quality release gates exist.
procedure Check_All is
   use Ada.Strings.Unbounded;
   Root : constant String := Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "improve.gpr");
   Check : constant Project_Tools.Release_Checks.Checker := Project_Tools.Release_Checks.Create (Root);
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

   procedure Require_Release_Dependency (Name, Constraint : String) is
   begin
      Check.Require_Text ("alire.release.toml", Name & " = """ & Constraint & """");
      if Name /= "gnat_native" then
         Check.Require_Text ("docs/dependency-licenses.md", "| " & Name & " |");
      end if;
   end Require_Release_Dependency;
begin
   if Root = "" then
      Project_Tools.Release_Checks.Fail ("cannot locate Improve project root");
   end if;
   for Path of Project_Tools.Files.List_Tree ("src", "*.ad?") loop Check_File (To_String (Path)); end loop;
   for Path of Project_Tools.Files.List_Tree ("tests/src", "*.ad?") loop Check_File (To_String (Path)); end loop;
   for Path of Project_Tools.Files.List_Tree ("tools/src", "*.ad?") loop Check_File (To_String (Path)); end loop;
   Check_File ("alire.toml");
   Check_File ("alire.release.toml");
   Check_File ("tests/alire.release.toml");
   Check_File ("improve.gpr");
   Check_File ("improve_docs.gpr");
   Check_File ("improve_spark.gpr");
   Check_File ("tests/coverage.gpr");
   Check_File ("tools/improve_tools.gpr");
   Check_File ("README.md");
   Check_File ("LICENSE");
   Check_File ("config/improve.toml");
   Check_File ("docs/release-readiness.md");
   Check_File ("docs/dependency-licenses.md");
   Check_File ("coverage/gcov-summary.txt");
   Reject_Non_Ada_Tooling ("*.sh");
   Reject_Non_Ada_Tooling ("*.py");
   Project_Tools.Alire_Manifests.Require_No_Local_Pins (Root & "/alire.release.toml");
   Check.Require_Text ("alire.toml", "version = ""0.1.0""");
   Check.Require_Text ("alire.release.toml", "version = ""0.1.0""");
   Check.Require_Text ("src/improve.ads", "Version : constant String := ""0.1.0"";");
   Check.Require_Text ("tests/alire.toml", "version = ""0.1.0""");
   Check.Require_Text ("tests/alire.release.toml", "version = ""0.1.0""");
   Check.Require_Text ("tests/alire.release.toml", "improve = { path = "".."" }");
   Check.Require_Text ("coverage/gcov-summary.txt", "complete=true");
   Check.Require_Text ("coverage/gcov-summary.txt", "inventory=gcov-production-lines-v2");
   Check.Require_Text ("CHANGELOG.md", "## 0.1.0 — 2026-11-03");
   Check.Require_Text ("LICENSE", "MIT License");
   Require_Release_Dependency ("gnat_native", "=15.2.1");
   Require_Release_Dependency ("database", "^0.14.0");
   Require_Release_Dependency ("ada_quality", "^0.1.0");
   Require_Release_Dependency ("jsonlib", "^0.1.0");
   Require_Release_Dependency ("messages", "^0.1.0");
   Require_Release_Dependency ("terminal_styles", "^0.1.0");
   Require_Release_Dependency ("project_tools", "^0.1.0");
   Require_Release_Dependency ("hostkit", "^0.1.0");
   Require_Release_Dependency ("model_runner", "^0.1.0");
   if Project_Tools.Files.File_Contains (Root & "/alire.toml", "[[pins]]") then
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "database", "../database");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "ada_quality", "../ada_quality");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "jsonlib", "../jsonlib");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "messages", "../messages");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin
        (Root & "/alire.toml", "terminal_styles", "../terminal_styles");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin
        (Root & "/alire.toml", "project_tools", "../project_tools");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "hostkit", "../hostkit");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin
        (Root & "/alire.toml", "model_runner", "../model_runner");
   else
      Project_Tools.Alire_Manifests.Require_No_Local_Pins (Root & "/alire.toml");
   end if;
   Check.Require_Text ("improve_spark.gpr", "Source_Files use (""improve.ads"", ""improve.adb"")");
   for Path of Project_Tools.Files.List_Tree ("src", "*.ad?") loop
      declare
         Name : constant String := Ada.Directories.Simple_Name (To_String (Path));
      begin
         if Project_Tools.Files.File_Contains (To_String (Path), "SPARK_Mode") and then
           Name not in "improve.ads" | "improve.adb"
         then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error, "SPARK unit is absent from improve_spark.gpr: " & To_String (Path));
            Failed := True;
         end if;
      end;
   end loop;
   if Project_Tools.Files.File_Contains ("alire.release.toml", "command = [""sh""") then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "release manifest contains shell tooling");
      Failed := True;
   end if;
   if Failed then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Ada.Text_IO.Put_Line ("repository checks passed");
   end if;
end Check_All;

