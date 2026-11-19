with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Project_Tools.Processes;

--  Exercise the installed command boundary rather than the in-process CLI API.
procedure Runtime_CLI_Black_Box is
   use Ada.Strings.Unbounded;

   Binary : constant String :=
     Ada.Directories.Full_Name
       (if Ada.Directories.Exists ("bin/improve-model-runner.exe")
        then "bin/improve-model-runner.exe"
        else "bin/improve-model-runner");

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then raise Program_Error with Message; end if;
   end Check;

   function Run
     (Arguments  : Project_Tools.Processes.Argument_Vectors.Vector;
      Err_To_Out : Boolean := False) return Project_Tools.Processes.Captured_Process is
     (Project_Tools.Processes.Capture_Command
        (Binary, Arguments, Err_To_Out => Err_To_Out));

   Help : constant Project_Tools.Processes.Captured_Process :=
     Run (Project_Tools.Processes.Arguments ([Project_Tools.Processes.Argument ("help")]));
   Version : constant Project_Tools.Processes.Captured_Process :=
     Run (Project_Tools.Processes.Arguments ([Project_Tools.Processes.Argument ("version")]));
   Invalid : constant Project_Tools.Processes.Captured_Process :=
     Run
       (Project_Tools.Processes.Arguments
          ([Project_Tools.Processes.Argument ("plan"),
            Project_Tools.Processes.Argument ("--definitely-not-an-option")]),
        Err_To_Out => True);
begin
   Check
     (Help.Status = 0 and then Ada.Strings.Fixed.Index (To_String (Help.Output), "Usage: improve") > 0,
      "black-box help did not write the documented standard output");
   Check
     (Version.Status = 0 and then Ada.Strings.Fixed.Index (To_String (Version.Output), "improve 0.1.0") > 0,
      "black-box version did not expose the runtime CLI version");
   Check
     (Invalid.Status = 2 and then Ada.Strings.Fixed.Index (To_String (Invalid.Output), "unknown option") > 0,
      "black-box invalid invocation did not preserve stderr and exit status 2");
end Runtime_CLI_Black_Box;
