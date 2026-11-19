with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Project_Tools.Files;

package body Improve_CI_Checks is
   procedure Validate_Action_Pins is
   begin
      for Path_Value of Project_Tools.Files.List_Tree (".github", "*.yml") loop
         declare
            Path  : constant String := Ada.Strings.Unbounded.To_String (Path_Value);
            Text  : constant String := Project_Tools.Files.Read_Raw_File (Path);
            Start : Natural := Text'First;
         begin
            while Start <= Text'Last loop
               declare
                  Stop : Natural := Start;
               begin
                  while Stop <= Text'Last and then Text (Stop) /= ASCII.LF loop
                     Stop := Stop + 1;
                  end loop;
                  declare
                     Line : constant String := Text (Start .. Stop - 1);
                     Uses : constant Natural := Ada.Strings.Fixed.Index (Line, "uses:");
                     At_Sign : constant Natural := Ada.Strings.Fixed.Index (Line, "@");
                  begin
                     if Uses > 0 and then Ada.Strings.Fixed.Index (Line, "uses: ./") = 0 and then
                       (At_Sign = 0 or else Line'Last - At_Sign < 40 or else
                        (for some Index in At_Sign + 1 .. At_Sign + 40 =>
                           Line (Index) not in '0' .. '9' | 'a' .. 'f'))
                     then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error, "GitHub Action is not commit-pinned: " & Path & ": " & Line);
                        raise Program_Error with "floating GitHub Action reference";
                     end if;
                  end;
                  Start := Stop + 1;
               end;
            end loop;
         end;
      end loop;
   end Validate_Action_Pins;
end Improve_CI_Checks;
