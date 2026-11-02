with Ada.Command_Line;
with Ada.Text_IO;
with Improve;

--  Minimal executable retained while the strict Phase 1 CLI is developed.
procedure Improve_Main is
begin
   Ada.Text_IO.Put_Line ("improve " & Improve.Version);
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
end Improve_Main;
