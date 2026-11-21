with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada_Quality.Checks;
with Ada_Quality.Coverage;
with Hostkit.Fs;
with Improve;
with Improve_Coverage_Units;
with Improve_Overlay_Identities;
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
   Project_Overlay : constant String := Ada.Environment_Variables.Value ("IMPROVE_GPR_OVERLAY", "");
   Project_Overlay_2 : constant String := Ada.Environment_Variables.Value ("IMPROVE_GPR_OVERLAY_2", "");
   Project_Overlay_3 : constant String := Ada.Environment_Variables.Value ("IMPROVE_GPR_OVERLAY_3", "");
   Project_Overlay_Identity : constant String := Ada.Environment_Variables.Value ("IMPROVE_GPR_OVERLAY_ID", "");
   Project_Overlay_2_Identity : constant String := Ada.Environment_Variables.Value ("IMPROVE_GPR_OVERLAY_2_ID", "");
   Project_Overlay_3_Identity : constant String := Ada.Environment_Variables.Value ("IMPROVE_GPR_OVERLAY_3_ID", "");
   Initial_Source_Fingerprint    : Unbounded_String;
   Initial_Overlay_1_Fingerprint : Unbounded_String;
   Initial_Overlay_2_Fingerprint : Unbounded_String;
   Initial_Overlay_3_Fingerprint : Unbounded_String;
   Initial_Overlay_1_Identity    : Unbounded_String;
   Initial_Overlay_2_Identity    : Unbounded_String;
   Initial_Overlay_3_Identity    : Unbounded_String;
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

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "coverage: " & Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      raise Program_Error with Message;
   end Fail;

   function Overlay_Fingerprint (Path : String) return String is
   begin
      if Path = "" then
         return "none";
      elsif not Project_Tools.Files.Directory_Exists (Path) then
         Fail ("dependency overlay is not a directory: " & Path);
      end if;
      return Ada_Quality.Checks.Source_Fingerprint (Path);
   end Overlay_Fingerprint;

   function Overlay_Identity (Path, Identity, Description : String) return String is
   begin
      if Path = "" then
         if Identity /= "" then
            Fail (Description & " identity was supplied without an overlay");
         end if;
         return "none";
      elsif Identity = "" then
         Fail (Description & " requires a stable identity such as dependency@commit");
      elsif not Improve_Overlay_Identities.Valid (Identity, Allow_None => False) then
         Fail (Description & " identity is invalid");
      end if;
      return Identity;
   end Overlay_Identity;

   function Build_Arguments return Project_Tools.Processes.Argument_Vectors.Vector is
      Result : Project_Tools.Processes.Argument_Vectors.Vector :=
        Project_Tools.Processes.Arguments
          ([Project_Tools.Processes.Argument ("exec"),
            Project_Tools.Processes.Argument ("--"),
            Project_Tools.Processes.Argument ("gprbuild"),
            Project_Tools.Processes.Argument ("-P"),
            Project_Tools.Processes.Argument ("coverage.gpr"),
            Project_Tools.Processes.Argument ("-XIMPROVE_COVERAGE_ROOT=" & Scratch)]);
   begin
      if Project_Overlay /= "" then
         Result.Append (Project_Tools.Processes.Argument ("-aP" & Project_Overlay));
      end if;
      if Project_Overlay_2 /= "" then
         Result.Append (Project_Tools.Processes.Argument ("-aP" & Project_Overlay_2));
      end if;
      if Project_Overlay_3 /= "" then
         Result.Append (Project_Tools.Processes.Argument ("-aP" & Project_Overlay_3));
      end if;
      Result.Append (Project_Tools.Processes.Argument ("-p"));
      Result.Append (Project_Tools.Processes.Argument ("-j1"));
      return Result;
   end Build_Arguments;

   procedure Require_Unchanged (Description, Initial, Current : String) is
   begin
      if Current /= Initial then
         Fail (Description & " changed while coverage was running");
      end if;
   end Require_Unchanged;
begin
   if Root = "" or else Alr = "" then Fail ("project root or Alire executable is unavailable"); end if;
   Initial_Source_Fingerprint := To_Unbounded_String (Ada_Quality.Checks.Source_Fingerprint (Root));
   Initial_Overlay_1_Fingerprint := To_Unbounded_String (Overlay_Fingerprint (Project_Overlay));
   Initial_Overlay_2_Fingerprint := To_Unbounded_String (Overlay_Fingerprint (Project_Overlay_2));
   Initial_Overlay_3_Fingerprint := To_Unbounded_String (Overlay_Fingerprint (Project_Overlay_3));
   Initial_Overlay_1_Identity :=
     To_Unbounded_String (Overlay_Identity (Project_Overlay, Project_Overlay_Identity, "first dependency overlay"));
   Initial_Overlay_2_Identity :=
     To_Unbounded_String
       (Overlay_Identity (Project_Overlay_2, Project_Overlay_2_Identity, "second dependency overlay"));
   Initial_Overlay_3_Identity :=
     To_Unbounded_String
       (Overlay_Identity (Project_Overlay_3, Project_Overlay_3_Identity, "third dependency overlay"));
   Project_Tools.Processes.Run
     ("instrumented Improve build", Tests_Dir, Alr, Build_Arguments);
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
            Object_Name : constant String := Improve_Coverage_Units.Compilation_Stem (Unit, Units) & ".gcno";
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
            for Path of Unit.Subunit_Paths loop
               Include (Path);
            end loop;
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
         Staged_Evidence : constant String := Evidence & ".improve.tmp";
         Evidence_Text : constant String :=
           "Lines executed:" & Project_Tools.Gcov.Percent_Image (Summary) & " of " & Trim (Total) & ASCII.LF &
           "covered=" & Trim (Covered) & ASCII.LF &
           "total=" & Trim (Total) & ASCII.LF &
           "complete=true" & ASCII.LF &
           "inventory=gcov-production-lines-v2" & ASCII.LF &
           "source_fingerprint=" & To_String (Initial_Source_Fingerprint) & ASCII.LF &
           "overlay_1_fingerprint=" & To_String (Initial_Overlay_1_Fingerprint) & ASCII.LF &
           "overlay_1_identity=" & To_String (Initial_Overlay_1_Identity) & ASCII.LF &
           "overlay_2_fingerprint=" & To_String (Initial_Overlay_2_Fingerprint) & ASCII.LF &
           "overlay_2_identity=" & To_String (Initial_Overlay_2_Identity) & ASCII.LF &
           "overlay_3_fingerprint=" & To_String (Initial_Overlay_3_Fingerprint) & ASCII.LF &
           "overlay_3_identity=" & To_String (Initial_Overlay_3_Identity) & ASCII.LF &
           "toolchain_fingerprint=" & Digest (Separator + 1 .. Digest'Last) & ASCII.LF;

         procedure Discard_Staged_Evidence is
         begin
            if Ada.Directories.Exists (Staged_Evidence) then
               Ada.Directories.Delete_File (Staged_Evidence);
            end if;
         exception
            when others => null;
         end Discard_Staged_Evidence;

         procedure Require_Inputs_Unchanged is
         begin
            Require_Unchanged
              ("Improve source", To_String (Initial_Source_Fingerprint), Ada_Quality.Checks.Source_Fingerprint (Root));
            Require_Unchanged
              ("first dependency overlay", To_String (Initial_Overlay_1_Fingerprint),
               Overlay_Fingerprint (Project_Overlay));
            Require_Unchanged
              ("second dependency overlay", To_String (Initial_Overlay_2_Fingerprint),
               Overlay_Fingerprint (Project_Overlay_2));
            Require_Unchanged
              ("third dependency overlay", To_String (Initial_Overlay_3_Fingerprint),
               Overlay_Fingerprint (Project_Overlay_3));
         end Require_Inputs_Unchanged;
      begin
         if Toolchain.Status /= 0 then Fail ("GNAT toolchain identity is unavailable"); end if;
         if not Project_Tools.Files.Directory_Exists (Evidence_Dir) then
            Ada.Directories.Create_Directory (Evidence_Dir);
         end if;
         Require_Inputs_Unchanged;
         Discard_Staged_Evidence;
         Project_Tools.Files.Write_Text_File (Staged_Evidence, Evidence_Text);
         Require_Inputs_Unchanged;
         if not Hostkit.Fs.Replace_File (Staged_Evidence, Evidence) then
            Fail ("could not atomically replace coverage evidence");
         end if;
      exception
         when others =>
            Discard_Staged_Evidence;
            raise;
      end;
   end;
   Project_Tools.Test_Fixtures.Cleanup (Scratch);
exception
   when others =>
      Project_Tools.Test_Fixtures.Cleanup (Scratch);
      raise;
end Improve_Coverage;
