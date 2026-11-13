with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Project_Tools.Files;

package body Improve_Coverage_Units is
   use Ada.Strings.Unbounded;

   function Stem_Of (Name : String) return String is
      Result : String := Ada.Characters.Handling.To_Lower (Name);
   begin
      for Index in Result'Range loop
         if Result (Index) = '.' then Result (Index) := '-'; end if;
      end loop;
      return Result;
   end Stem_Of;

   function Separate_Parent (Path : String) return String is
      Text  : constant String := Project_Tools.Files.Read_Raw_File (Path);
      Index : Natural := Text'First;

      function Identifier_Character (Value : Character) return Boolean is
        (Value in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_');

      procedure Skip_Trivia (Position : in out Natural) is
      begin
         loop
            while Position <= Text'Last and then Text (Position) in ' ' | ASCII.HT | ASCII.CR | ASCII.LF loop
               Position := Position + 1;
            end loop;
            exit when Position >= Text'Last or else
              Text (Position) /= '-' or else Text (Position + 1) /= '-';
            while Position <= Text'Last and then Text (Position) /= ASCII.LF loop
               Position := Position + 1;
            end loop;
         end loop;
      end Skip_Trivia;
   begin
      while Index <= Text'Last loop
         if Index < Text'Last and then Text (Index) = '-' and then Text (Index + 1) = '-' then
            while Index <= Text'Last and then Text (Index) /= ASCII.LF loop
               Index := Index + 1;
            end loop;
         elsif Text (Index) = '"' then
            Index := Index + 1;
            while Index <= Text'Last loop
               if Text (Index) = '"' then
                  if Index < Text'Last and then Text (Index + 1) = '"' then
                     Index := Index + 2;
                  else
                     Index := Index + 1;
                     exit;
                  end if;
               else
                  Index := Index + 1;
               end if;
            end loop;
         elsif Identifier_Character (Text (Index)) then
            declare First : constant Positive := Index; begin
               while Index <= Text'Last and then Identifier_Character (Text (Index)) loop
                  Index := Index + 1;
               end loop;
               if Ada.Characters.Handling.To_Lower (Text (First .. Index - 1)) = "separate" then
                  declare
                     Position : Natural := Index;
                     Parent   : Unbounded_String;
                  begin
                     Skip_Trivia (Position);
                     if Position <= Text'Last and then Text (Position) = '(' then
                        Position := Position + 1;
                        loop
                           Skip_Trivia (Position);
                           if Position > Text'Last then
                              raise Program_Error with "unterminated Ada separate parent in " & Path;
                           elsif Text (Position) = ')' then
                              if Length (Parent) = 0 then
                                 raise Program_Error with "empty Ada separate parent in " & Path;
                              end if;
                              return To_String (Parent);
                           elsif Identifier_Character (Text (Position)) or else Text (Position) = '.' then
                              Append (Parent, Ada.Characters.Handling.To_Lower (Text (Position)));
                              Position := Position + 1;
                           else
                              raise Program_Error with "malformed Ada separate parent in " & Path;
                           end if;
                        end loop;
                     end if;
                  end;
               end if;
            end;
         else
            Index := Index + 1;
         end if;
      end loop;
      return "";
   end Separate_Parent;

   function Compilation_Stem
     (Unit : Ada_Quality.Coverage.Production_Unit) return String is
   begin
      if Length (Unit.Body_Path) = 0 then return To_String (Unit.Stem); end if;
      declare
         Current : Unbounded_String := Unit.Body_Path;
         Parent  : Unbounded_String := To_Unbounded_String (Separate_Parent (To_String (Unit.Body_Path)));
      begin
         if Length (Parent) = 0 then return To_String (Unit.Stem); end if;
         for Depth in 1 .. 32 loop
            declare
               Stem : constant String := Stem_Of (To_String (Parent));
               Parent_Source : constant String :=
                 Project_Tools.Files.Join
                   (Ada.Directories.Containing_Directory (To_String (Current)), Stem & ".adb");
            begin
               if not Project_Tools.Files.File_Exists (Parent_Source) then return Stem; end if;
               declare Next_Parent : constant String := Separate_Parent (Parent_Source); begin
                  if Next_Parent = "" then return Stem; end if;
                  if Depth = 32 then
                     raise Program_Error with "Ada separate parent nesting exceeds coverage limit";
                  elsif Parent_Source = To_String (Current) then
                     raise Program_Error with "cyclic Ada separate parent " & Next_Parent;
                  end if;
                  Current := To_Unbounded_String (Parent_Source);
                  Parent := To_Unbounded_String (Next_Parent);
               end;
            end;
         end loop;
         raise Program_Error with "Ada separate parent nesting exceeds coverage limit";
      end;
   end Compilation_Stem;
end Improve_Coverage_Units;
