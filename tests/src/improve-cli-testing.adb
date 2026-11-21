with Ada.Strings.Unbounded;
with Improve.CLI_Support;
with Project_Tools.Files;

package body Improve.CLI.Testing is
   use Ada.Strings.Unbounded;

   Target_Path      : Unbounded_String;
   Replacement_Text : Unbounded_String;

   procedure Replace_After_First_Pass (Completed_Pass : Positive) is
   begin
      if Completed_Pass = 1 then
         Project_Tools.Files.Write_Text_File (To_String (Target_Path), To_String (Replacement_Text));
      end if;
   end Replace_After_First_Pass;

   function Rejects_Between_Pass_Change
     (Path, Replacement : String;
      Maximum_Bytes     : Positive) return Boolean is
   begin
      Target_Path := To_Unbounded_String (Path);
      Replacement_Text := To_Unbounded_String (Replacement);
      declare
         Text : constant String :=
           Improve.CLI_Support.Read_Bounded_File
             (Path, "test input", Maximum_Bytes, Replace_After_First_Pass'Access);
         pragma Unreferenced (Text);
      begin
         return False;
      end;
   exception
      when Improve.Dependency_Error => return True;
   end Rejects_Between_Pass_Change;
end Improve.CLI.Testing;
