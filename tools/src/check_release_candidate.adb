with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada_Quality.Checks;
with Ada_Quality.Policy;
with Ada_Quality.Types;
with Project_Tools.Alire_Manifests;
with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Release_Checks;
with Project_Tools.Test_Fixtures;

--  Ada-only clean-source, pin-free release and complete Ada Quality assessment gate.
procedure Check_Release_Candidate is
   use Ada.Strings.Unbounded;
   use type Ada_Quality.Types.Compliance_Status;
   use type Ada_Quality.Types.Execution_Status;

   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "improve.gpr");
   Stage : constant String := Project_Tools.Test_Fixtures.Fresh_Temp_Dir ("improve-release-candidate");
   Alr : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Policy : Ada_Quality.Policy.Quality_Policy := Ada_Quality.Policy.Default;

   procedure Run_Alr (Label, Directory : String; Arguments : Project_Tools.Processes.Argument_Items) is
   begin
      Project_Tools.Processes.Run
        (Label, Directory, Alr, Project_Tools.Processes.Arguments (Arguments));
   end Run_Alr;

   procedure Require_Passing_Assessment (Value : Ada_Quality.Types.Assessment) is
      Failed : Boolean := False;
   begin
      if not Ada_Quality.Types.Is_Publishable (Value) then
         raise Program_Error with "Ada Quality returned an incomplete or invalid assessment";
      end if;
      for Result of Value.Results loop
         Ada.Text_IO.Put_Line
           ("  " & Ada_Quality.Types.Image (Result.Indicator) & " " &
            Ada_Quality.Types.Image (Result.Execution) & "/" &
            Ada_Quality.Types.Image (Result.Compliance));
         if not
           ((Result.Execution = Ada_Quality.Types.Succeeded and then
              Result.Compliance = Ada_Quality.Types.Pass)
            or else
              (Result.Execution = Ada_Quality.Types.Not_Applicable and then
                 Result.Compliance = Ada_Quality.Types.Not_Applicable))
         then
            Failed := True;
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error, "    " & To_String (Result.Summary));
         end if;
      end loop;
      if Failed then
         raise Program_Error with "release candidate does not satisfy the complete Ada Quality policy";
      end if;
   end Require_Passing_Assessment;
begin
   if Root = "" or else Alr = "" then
      raise Program_Error with "project root or Alire is unavailable";
   end if;
   Project_Tools.Release_Checks.Require_Clean_Git_Worktree ("Improve", Root);
   Project_Tools.Files.Copy_Release_Source_Tree
     (Source_Dir   => Root,
      Target_Dir   => Stage,
      Skip_Entries =>
        [To_Unbounded_String (".git"), To_Unbounded_String ("alire"), To_Unbounded_String ("obj"),
         To_Unbounded_String ("bin"), To_Unbounded_String ("lib"), To_Unbounded_String ("dist"),
         To_Unbounded_String ("proof"), To_Unbounded_String ("coverage")],
      Skip_Files   => [1 => To_Unbounded_String ("alire.toml")]);
   Project_Tools.Alire_Manifests.Copy_Release_Manifest
     (Root & "/alire.release.toml", Stage & "/alire.toml");
   Project_Tools.Alire_Manifests.Copy_Release_Manifest
     (Root & "/tests/alire.release.toml", Stage & "/tests/alire.toml");
   Project_Tools.Alire_Manifests.Require_Pin_Free_Crate_Manifest
     (Stage & "/alire.toml", "improve");
   Run_Alr
     ("pin-free dependency resolution", Stage,
      [1 => Project_Tools.Processes.Argument ("update")]);
   Run_Alr
     ("pin-free release build", Stage,
      [Project_Tools.Processes.Argument ("build"), Project_Tools.Processes.Argument ("--validation"),
       Project_Tools.Processes.Argument ("--"), Project_Tools.Processes.Argument ("-j1")]);
   Run_Alr
     ("release test dependency resolution", Stage & "/tests",
      [1 => Project_Tools.Processes.Argument ("update")]);
   Run_Alr
     ("release test build", Stage & "/tests",
      [Project_Tools.Processes.Argument ("build"), Project_Tools.Processes.Argument ("--validation"),
       Project_Tools.Processes.Argument ("--"), Project_Tools.Processes.Argument ("-j1")]);
   Run_Alr
     ("release tooling build", Stage,
      [Project_Tools.Processes.Argument ("exec"), Project_Tools.Processes.Argument ("--"),
       Project_Tools.Processes.Argument ("gprbuild"), Project_Tools.Processes.Argument ("-P"),
       Project_Tools.Processes.Argument ("tools/improve_tools.gpr"), Project_Tools.Processes.Argument ("-p"),
       Project_Tools.Processes.Argument ("-j1")]);
   Project_Tools.Processes.Run
     ("release coverage evidence", Stage, Stage & "/tools/bin/improve_coverage",
      Project_Tools.Processes.No_Arguments);
   Policy.Require_Clean_Worktree := False;
   Require_Passing_Assessment (Ada_Quality.Checks.Assess (1, Stage, Policy));
   Project_Tools.Test_Fixtures.Cleanup (Stage);
   Ada.Text_IO.Put_Line ("clean pin-free release candidate passed all 33 Ada Quality indicators");
exception
   when others =>
      Project_Tools.Test_Fixtures.Cleanup (Stage);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      raise;
end Check_Release_Candidate;
