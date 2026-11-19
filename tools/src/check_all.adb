with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada_Quality.Checks;
with Improve_CI_Checks;
with Project_Tools.Alire_Manifests;
with Project_Tools.Files;
with Project_Tools.Release_Checks;

--  Fast repository checks used before the deeper Ada Quality release gates exist.
procedure Check_All is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   Root : constant String := Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "improve.gpr");
   Check : constant Project_Tools.Release_Checks.Checker := Project_Tools.Release_Checks.Create (Root);
   Failed : Boolean := False;

   package Text_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Unbounded_String);

   procedure Check_File (Path : String; Maximum_Lines : Natural := 0) is
   begin
      if not Project_Tools.Files.File_Exists (Path) then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "missing required file: " & Path);
         Failed := True;
         return;
      end if;
      declare
         Text   : constant String := Project_Tools.Files.Read_Raw_File (Path);
         Column : Natural := 0;
         Lines  : Natural := (if Text = "" then 0 else 1);
      begin
         for C of Text loop
            if C = Character'Val (10) then
               Column := 0;
               Lines := Lines + 1;
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
         if Maximum_Lines > 0 and then Lines > Maximum_Lines then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "source exceeds structural line limit:" & Natural'Image (Lines) & " " & Path);
            Failed := True;
         end if;
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

   function Evidence_Value (Name : String) return String is
      Text   : constant String := Project_Tools.Files.Read_Raw_File ("coverage/gcov-summary.txt");
      Prefix : constant String := Name & "=";
      Start  : Natural := Text'First;
   begin
      while Start <= Text'Last loop
         declare Stop : Natural := Start; begin
            while Stop <= Text'Last and then Text (Stop) /= ASCII.LF loop
               Stop := Stop + 1;
            end loop;
            if Stop - Start >= Prefix'Length and then Text (Start .. Start + Prefix'Length - 1) = Prefix then
               return Text (Start + Prefix'Length .. Stop - 1);
            end if;
            Start := Stop + 1;
         end;
      end loop;
      return "";
   end Evidence_Value;

   procedure Validate_Dependency_Lock is
      Text  : constant String := Project_Tools.Files.Read_Raw_File (".github/dependency-lock.txt");
      Lines : Text_Vectors.Vector;
      Start : Natural := Text'First;

      procedure Report (Message : String) is
      begin
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "dependency lock: " & Message);
         Failed := True;
      end Report;

      procedure Require_Repository (Name : String) is
         Matches : Natural := 0;
      begin
         for Line of Lines loop
            declare Value : constant String := To_String (Line); begin
               if Value'Length > Name'Length and then
                 Value (Value'First .. Value'First + Name'Length) = Name & "="
               then
                  Matches := Matches + 1;
               end if;
            end;
         end loop;
         if Matches /= 1 then
            Report (Name & " must have exactly one pinned revision");
         end if;
      end Require_Repository;
   begin
      while Start <= Text'Last loop
         declare Stop : Natural := Start; begin
            while Stop <= Text'Last and then Text (Stop) /= ASCII.LF loop
               Stop := Stop + 1;
            end loop;
            if Stop > Start then Lines.Append (To_Unbounded_String (Text (Start .. Stop - 1))); end if;
            Start := Stop + 1;
         end;
      end loop;
      if Lines.Length /= 19 then
         Report ("expected 19 workspace repositories, found" & Natural'Image (Natural (Lines.Length)));
      end if;
      for Line of Lines loop
         declare
            Value : constant String := To_String (Line);
            Equal : Natural := 0;
         begin
            for Index in Value'Range loop
               if Value (Index) = '=' then Equal := Index; exit; end if;
            end loop;
            if Equal = 0 or else Value'Last - Equal /= 40 or else
              (for some Index in Equal + 1 .. Value'Last =>
                 Value (Index) not in '0' .. '9' | 'a' .. 'f')
            then
               Report ("invalid repository=commit entry: " & Value);
            end if;
         end;
      end loop;
      Require_Repository ("ada_quality");
      Require_Repository ("database");
      Require_Repository ("jsonlib");
      Require_Repository ("messages");
      Require_Repository ("terminal_styles");
      Require_Repository ("project_tools");
      Require_Repository ("hostkit");
      Require_Repository ("model_runner");
      Require_Repository ("cryptolib");
      Require_Repository ("i18n");
      Require_Repository ("regexp");
      Require_Repository ("httpclient");
      Require_Repository ("ssllib");
      Require_Repository ("truststores");
      Require_Repository ("zlib");
      Require_Repository ("jpeglib");
      Require_Repository ("versionlib");
      Require_Repository ("sshlib");
      Require_Repository ("awklib");
   end Validate_Dependency_Lock;
begin
   if Root = "" then
      Project_Tools.Release_Checks.Fail ("cannot locate Improve project root");
   end if;
   for Path of Project_Tools.Files.List_Tree ("src", "*.ad?") loop
      Check_File (To_String (Path), Maximum_Lines => 700);
   end loop;
   for Path of Project_Tools.Files.List_Tree ("tests/src", "*.ad?") loop
      Check_File (To_String (Path), Maximum_Lines => 650);
   end loop;
   for Path of Project_Tools.Files.List_Tree ("tools/src", "*.ad?") loop
      Check_File (To_String (Path), Maximum_Lines => 300);
   end loop;
   Check_File ("alire.toml");
   Check_File ("alire.release.toml");
   Check_File ("model_runner_runtime/alire.release.toml");
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
   Check_File ("docs/improve.1");
   Check_File ("docs/dependency-licenses.md");
   Check_File ("schemas/improve-output-v1.schema.json");
   Check_File ("completions/improve.bash");
   Check_File ("completions/_improve");
   Check_File ("completions/improve.fish");
   Check_File (".github/workflows/release.yml");
   Check_File (".github/workflows/ci.yml");
   Check_File (".github/dependency-lock.txt");
   Check_File ("coverage/gcov-summary.txt");
   Reject_Non_Ada_Tooling ("*.sh");
   Reject_Non_Ada_Tooling ("*.py");
   Project_Tools.Alire_Manifests.Require_No_Local_Pins (Root & "/alire.release.toml");
   Project_Tools.Alire_Manifests.Require_No_Local_Pins
     (Root & "/model_runner_runtime/alire.release.toml");
   Check.Require_Text ("alire.toml", "version = ""0.1.0""");
   Check.Require_Text ("alire.release.toml", "version = ""0.1.0""");
   Check.Require_Text
     ("model_runner_runtime/alire.release.toml", "gnat_native = ""=15.2.1""");
   Check.Require_Text
     ("model_runner_runtime/alire.release.toml", "model_runner = ""^0.1.0""");
   Check.Require_Text ("src/improve.ads", "Version : constant String := ""0.1.0"";");
   Check.Require_Text ("tests/alire.toml", "version = ""0.1.0""");
   Check.Require_Text ("tests/alire.release.toml", "version = ""0.1.0""");
   Check.Require_Text ("tests/alire.release.toml", "improve = { path = "".."" }");
   Check.Require_Text ("coverage/gcov-summary.txt", "complete=true");
   Check.Require_Text ("coverage/gcov-summary.txt", "inventory=gcov-production-lines-v2");
   Validate_Dependency_Lock;
   Improve_CI_Checks.Validate_Action_Pins;
   Improve_CI_Checks.Validate_Workflow_Contracts;
   if Evidence_Value ("source_fingerprint") /= Ada_Quality.Checks.Source_Fingerprint (Root) then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "coverage evidence does not match current source fingerprint " &
         Ada_Quality.Checks.Source_Fingerprint (Root));
      Failed := True;
   end if;
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
   Require_Release_Dependency ("model_runner_framework", "^0.1.0");
   Require_Release_Dependency ("cryptolib", "^0.1.0");
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
        (Root & "/alire.toml", "model_runner_framework", "../model_runner/framework");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "cryptolib", "../cryptolib");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "i18n", "../i18n");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "regexp", "../regexp");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "httpclient", "../httpclient");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "ssllib", "../ssllib");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin
        (Root & "/alire.toml", "truststores", "../truststores");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "zlib", "../zlib");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "jpeglib", "../jpeglib");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin
        (Root & "/alire.toml", "versionlib", "../versionlib");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "ssh_lib", "../sshlib");
      Project_Tools.Alire_Manifests.Require_Workspace_Pin (Root & "/alire.toml", "awklib", "../awklib");
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

