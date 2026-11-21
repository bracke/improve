with Ada.Strings.Fixed;

package body Improve_Overlay_Identities is
   function Valid (Value : String; Allow_None : Boolean := True) return Boolean is
      function Valid_Name_Character (Item : Character) return Boolean is
        (Item in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '_' | '-');

      function Valid_Commit_Character (Item : Character) return Boolean is
        (Item in '0' .. '9' | 'a' .. 'f');

      function Valid_Entry (Text : String) return Boolean is
         Separator : constant Natural := Ada.Strings.Fixed.Index (Text, "@");
      begin
         if Separator = 0 or else Separator = Text'First or else Separator = Text'Last then
            return False;
         end if;
         declare
            Name   : constant String := Text (Text'First .. Separator - 1);
            Commit : constant String := Text (Separator + 1 .. Text'Last);
         begin
            return
              Ada.Strings.Fixed.Index (Commit, "@") = 0 and then
              (for all Item of Name => Valid_Name_Character (Item)) and then
              Commit'Length in 40 | 64 and then
              (for all Item of Commit => Valid_Commit_Character (Item));
         end;
      end Valid_Entry;

      Start : Natural := Value'First;
   begin
      if Value = "none" then
         return Allow_None;
      elsif Value = "" or else Value'Length > 512 then
         return False;
      end if;
      while Start <= Value'Last loop
         declare
            Comma : constant Natural := Ada.Strings.Fixed.Index (Value (Start .. Value'Last), ",");
            Last  : constant Natural := (if Comma = 0 then Value'Last else Comma - 1);
         begin
            if Last < Start or else not Valid_Entry (Value (Start .. Last)) then
               return False;
            end if;
            exit when Comma = 0;
            Start := Comma + 1;
            if Start > Value'Last then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Valid;
end Improve_Overlay_Identities;
