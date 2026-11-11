with Ada.Command_Line;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada_Quality.Checks;
with Ada_Quality.Coverage;
with Improve;
with Project_Tools.Files;
with Project_Tools.Gcov;
with Project_Tools.Processes;
with Project_Tools.Test_Fixtures;

--  Build and run the instrumented suite, then require complete 90% production line coverage.
procedure Improve_Coverage is
   use Ada.Strings.Unbounded;

   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "improve.gpr");
   Tests_Dir : constant String := Project_Tools.Files.Join (Root, "tests");
   Scratch : constant String := Project_Tools.Test_Fixtures.Fresh_Temp_Dir ("improve-coverage");
   Object_Dir : constant String := Project_Tools.Files.Join (Scratch, "obj");
   Binary_Dir : constant String := Project_Tools.Files.Join (Scratch, "bin");
   Alr : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Covered : Natural := 0;
   Total   : Natural := 0;

   function Trim (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Per_File_Output (Text : String) return String is
      Aggregate : constant Natural := Ada.Strings.Fixed.Index
        (Text, ASCII.LF & "Lines executed:", Going => Ada.Strings.Backward);
   begin
      return (if Aggregate = 0 then Text else Text (Text'First .. Aggregate - 1));
   end Per_File_Output;

   function Is_Reviewed_Empty_Namespace
     (Unit : Ada_Quality.Coverage.Production_Unit) return Boolean is
     (To_String (Unit.Stem) = "improve-operations" and then
      Length (Unit.Body_Path) = 0);

   function Compilation_Stem
     (Unit : Ada_Quality.Coverage.Production_Unit) return String is
      Prefix : constant String := "separate (";
   begin
      if Length (Unit.Body_Path) > 0 then
         declare
            Text : constant String :=
              Project_Tools.Files.Read_Raw_File (To_String (Unit.Body_Path));
         begin
            if Text'Length > Prefix'Length and then
              Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix
            then
               declare
                  Closing : constant Natural :=
                    Ada.Strings.Fixed.Index
                      (Text, ")", From => Text'First + Prefix'Length);
               begin
                  if Closing > Text'First + Prefix'Length then
                     declare
                        Result : String :=
                          Ada.Characters.Handling.To_Lower
                            (Text (Text'First + Prefix'Length .. Closing - 1));
                     begin
                        for Index in Result'Range loop
                           if Result (Index) = '.' then
                              Result (Index) := '-';
                           end if;
                        end loop;
                        return Result;
                     end;
                  end if;
               end;
            end if;
         end;
      end if;
      return To_String (Unit.Stem);
   end Compilation_Stem;

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "coverage: " & Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      raise Program_Error with Message;
   end Fail;
begin
   if Root = "" or else Alr = "" then Fail ("project root or Alire executable is unavailable"); end if;
   Project_Tools.Processes.Run
     ("instrumented Improve build", Tests_Dir, Alr,
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("exec"),
          Project_Tools.Processes.Argument ("--"),
          Project_Tools.Processes.Argument ("gprbuild"),
          Project_Tools.Processes.Argument ("-P"),
          Project_Tools.Processes.Argument ("coverage.gpr"),
          Project_Tools.Processes.Argument ("-XIMPROVE_COVERAGE_ROOT=" & Scratch),
          Project_Tools.Processes.Argument ("-p"),
          Project_Tools.Processes.Argument ("-j1")]));
   Project_Tools.Processes.Run
     ("instrumented AUnit suite", Tests_Dir,
      Project_Tools.Files.Join (Binary_Dir, "improve_tests"), Project_Tools.Processes.No_Arguments);
   Project_Tools.Processes.Run
     ("instrumented CLI smoke test", Root,
      Project_Tools.Files.Join (Binary_Dir, "improve"),
      Project_Tools.Processes.Arguments ([Project_Tools.Processes.Argument ("help")]));
   declare
      Units   : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
        Ada_Quality.Coverage.Production_Units (Root);
   begin
      if Units.Is_Empty then Fail ("production source inventory is empty"); end if;
      for Unit of Units loop
         declare
            Object_Name : constant String := Compilation_Stem (Unit) & ".gcno";
            Run : constant Project_Tools.Processes.Captured_Process :=
              Project_Tools.Processes.Capture
                ("gcov " & Object_Name, Root, Alr,
                 Project_Tools.Processes.Arguments
                   ([Project_Tools.Processes.Argument ("exec"),
                     Project_Tools.Processes.Argument ("--"),
                     Project_Tools.Processes.Argument ("gcov"),
                     Project_Tools.Processes.Argument ("-n"),
                     Project_Tools.Processes.Argument ("-o"),
                     Project_Tools.Processes.Argument (Object_Dir),
                     Project_Tools.Processes.Argument (Project_Tools.Files.Join (Object_Dir, Object_Name))]));
            Output : constant String := Per_File_Output (To_String (Run.Output));
            Unit_Covered : Natural := 0;
            Unit_Total   : Natural := 0;
            Has_Record   : Boolean := False;

            procedure Include (Path : Unbounded_String) is
               Summary : Project_Tools.Gcov.Coverage_Summary;
            begin
               if Length (Path) = 0 or else
                 not Ada_Quality.Coverage.Has_Source_Record (Output, To_String (Path))
               then
                  return;
               end if;
               Summary := Project_Tools.Gcov.Parse_Lines_Executed_Output (Output, To_String (Path));
               Unit_Covered := Unit_Covered + Project_Tools.Gcov.Covered_Lines (Summary);
               Unit_Total := Unit_Total + Project_Tools.Gcov.Total_Lines (Summary);
               Has_Record := True;
            end Include;
         begin
            if not Project_Tools.Files.File_Exists
              (Project_Tools.Files.Join (Object_Dir, Object_Name))
            then
               Fail ("instrumented data is missing for " & To_String (Unit.Stem));
            end if;
            if Run.Status /= 0 then Fail ("gcov failed for " & Object_Name); end if;
            Include (Unit.Body_Path);
            Include (Unit.Spec_Path);
            --  GNAT emits no source record for an empty namespace specification.
            --  Keep this exception explicit so a new spec-only implementation
            --  cannot silently disappear from the coverage denominator.
            if not Has_Record and then not Is_Reviewed_Empty_Namespace (Unit) then
               Fail ("gcov output is incomplete for " & To_String (Unit.Stem));
            end if;
            Covered := Covered + Unit_Covered;
            Total := Total + Unit_Total;
            Ada.Text_IO.Put_Line
              ("  " & To_String (Unit.Stem) & " " & Trim (Unit_Covered) & "/" & Trim (Unit_Total));
         end;
      end loop;
   end;
   declare
      Summary : constant Project_Tools.Gcov.Coverage_Summary := Project_Tools.Gcov.Summary (Covered, Total);
      Errors  : Natural := 0;
   begin
      Project_Tools.Gcov.Require_Minimum_Line_Coverage
        (Errors, Summary, Minimum_Basis_Points => 9_000, Minimum_Executable_Lines => 1,
         Purpose => "Improve production line coverage");
      Ada.Text_IO.Put_Line
        ("coverage " & Trim (Covered) & "/" & Trim (Total) & " (" &
         Project_Tools.Gcov.Percent_Image (Summary) & ")");
      if Errors > 0 then Fail ("production coverage is below 90.00%"); end if;
      declare
         Toolchain : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture
             ("GNAT toolchain identity", Root, Alr,
              Project_Tools.Processes.Arguments
                ([Project_Tools.Processes.Argument ("exec"),
                  Project_Tools.Processes.Argument ("--"),
                  Project_Tools.Processes.Argument ("gnatls"),
                  Project_Tools.Processes.Argument ("--version")]));
         Digest : constant String := Improve.Stable_Digest (To_String (Toolchain.Output));
         Separator : constant Natural := Ada.Strings.Fixed.Index (Digest, ":");
         Evidence_Dir : constant String := Project_Tools.Files.Join (Root, "coverage");
         Evidence : constant String := Project_Tools.Files.Join (Evidence_Dir, "gcov-summary.txt");
      begin
         if Toolchain.Status /= 0 then Fail ("GNAT toolchain identity is unavailable"); end if;
         if not Project_Tools.Files.Directory_Exists (Evidence_Dir) then
            Ada.Directories.Create_Directory (Evidence_Dir);
         end if;
         Project_Tools.Files.Write_Text_File
           (Evidence,
            "Lines executed:" & Project_Tools.Gcov.Percent_Image (Summary) & " of " & Trim (Total) & ASCII.LF &
            "covered=" & Trim (Covered) & ASCII.LF &
            "total=" & Trim (Total) & ASCII.LF &
            "complete=true" & ASCII.LF &
            "inventory=gcov-production-lines-v2" & ASCII.LF &
            "source_fingerprint=" & Ada_Quality.Checks.Source_Fingerprint (Root) & ASCII.LF &
            "toolchain_fingerprint=" & Digest (Separator + 1 .. Digest'Last) & ASCII.LF);
      end;
   end;
   Project_Tools.Test_Fixtures.Cleanup (Scratch);
exception
   when others =>
      Project_Tools.Test_Fixtures.Cleanup (Scratch);
      raise;
end Improve_Coverage;
