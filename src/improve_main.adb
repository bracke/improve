with Ada.Command_Line;
with Improve.CLI;

--  Thin executable adapter for Improve.CLI.
procedure Improve_Main is
   --  CLI process entry point.
begin
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Improve.CLI.Run));
end Improve_Main;
