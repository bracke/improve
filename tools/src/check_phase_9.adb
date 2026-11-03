with Ada.Command_Line;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Test_Fixtures;

--  Ada-only Phase 9 release gate over builds, tests, docs, proof, coverage, and repository policy.
procedure Check_Phase_9 is
   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "improve.gpr");
   Tests : constant String := Project_Tools.Files.Join (Root, "tests");
   Tools : constant String := Project_Tools.Files.Join (Root, "tools/bin");
   Docs  : constant String := Project_Tools.Test_Fixtures.Fresh_Temp_Dir ("improve-gnatdoc");
   Alr   : constant String := Project_Tools.Processes.Locate_Command ("alr");
begin
   if Root = "" or else Alr = "" then raise Program_Error with "project root or Alire is unavailable"; end if;
   Project_Tools.Processes.Run
     ("validation build", Root, Alr,
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("build"),
          Project_Tools.Processes.Argument ("--validation"),
          Project_Tools.Processes.Argument ("--"),
          Project_Tools.Processes.Argument ("-j1")]));
   Project_Tools.Processes.Run
     ("validation test build", Tests, Alr,
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("build"),
          Project_Tools.Processes.Argument ("--validation"),
          Project_Tools.Processes.Argument ("--"),
          Project_Tools.Processes.Argument ("-j1")]));
   Project_Tools.Processes.Run
     ("AUnit suite", Tests, Project_Tools.Files.Join (Tests, "bin/improve_tests"),
      Project_Tools.Processes.No_Arguments);
   Project_Tools.Processes.Run
     ("repository release checks", Root, Project_Tools.Files.Join (Tools, "check_all"),
      Project_Tools.Processes.No_Arguments);
   Ada.Text_IO.Put_Line (ASCII.LF & "==> GNATdoc public API audit");
   declare
      Run : constant Project_Tools.Processes.Captured_Process :=
        Project_Tools.Processes.Capture_Command
          (Alr,
           Project_Tools.Processes.Arguments
             ([Project_Tools.Processes.Argument ("exec"),
               Project_Tools.Processes.Argument ("--"),
               Project_Tools.Processes.Argument ("gnatdoc"),
               Project_Tools.Processes.Argument ("-P"),
               Project_Tools.Processes.Argument ("improve.gpr"),
               Project_Tools.Processes.Argument ("-O"),
               Project_Tools.Processes.Argument (Docs),
               Project_Tools.Processes.Argument ("--generate"),
               Project_Tools.Processes.Argument ("public"),
               Project_Tools.Processes.Argument ("--warnings")]),
           Err_To_Out => True);
      Output : constant String := Ada.Strings.Unbounded.To_String (Run.Output);
   begin
      if Run.Status /= 0 or else
        Ada.Strings.Fixed.Index (Ada.Characters.Handling.To_Lower (Output), "warning:") > 0
      then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Output);
         raise Program_Error with "GNATdoc public API audit emitted diagnostics";
      end if;
   end;
   Project_Tools.Processes.Run
     ("GNATprove digest proof", Root, Alr,
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("exec"),
          Project_Tools.Processes.Argument ("--"),
          Project_Tools.Processes.Argument ("gnatprove"),
          Project_Tools.Processes.Argument ("-P"),
          Project_Tools.Processes.Argument ("improve_spark.gpr"),
          Project_Tools.Processes.Argument ("--mode=prove"),
          Project_Tools.Processes.Argument ("--level=2"),
          Project_Tools.Processes.Argument ("-j1")]));
   Project_Tools.Processes.Run
     ("production coverage", Root, Project_Tools.Files.Join (Tools, "improve_coverage"),
      Project_Tools.Processes.No_Arguments);
   Project_Tools.Test_Fixtures.Cleanup (Docs);
   Ada.Text_IO.Put_Line ("Phase 9 release gate passed");
exception
   when others =>
      Project_Tools.Test_Fixtures.Cleanup (Docs);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      raise;
end Check_Phase_9;
