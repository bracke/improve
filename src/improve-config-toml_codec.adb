separate (Improve.Config)
package body TOML_Codec is
   procedure Parse
     (Text    : String;
      Entries : out Entry_Array;
      Present : out Presence_Array) is
      Current_Section : UString;
      Section_Seen    : Presence_Array := [others => False];
      Start           : Natural := Text'First;

      procedure Mark_Section (Name : String) is
      begin
         for Id in Setting_Id loop
            if To_String (Definitions (Id).Section) = Name and then Section_Seen (Id) then
               raise Argument_Error with "duplicate configuration section: " & Name;
            end if;
         end loop;
         for Id in Setting_Id loop
            if To_String (Definitions (Id).Section) = Name then
               Section_Seen (Id) := True;
            end if;
         end loop;
      end Mark_Section;
   begin
      Entries := [others => Null_Unbounded_String];
      Present := [others => False];
      while Start <= Text'Last loop
         declare
            Stop : Natural := Start;
         begin
            while Stop <= Text'Last and then Text (Stop) /= LF loop
               Stop := Stop + 1;
            end loop;
            declare
               Last : Natural := Stop - 1;
            begin
               if Last >= Start and then Text (Last) = ASCII.CR then
                  Last := Last - 1;
               end if;
               declare
                  Line : constant String :=
                    (if Last < Start then ""
                     else Ada.Strings.Fixed.Trim (Text (Start .. Last), Ada.Strings.Both));
               begin
                  if Line = "" or else Line (Line'First) = '#' then
                     null;
                  elsif Line (Line'First) = '[' then
                     declare
                        Close : constant Natural := Ada.Strings.Fixed.Index (Line, "]");
                     begin
                        if Line'Length < 3 or else Close = 0 or else Line (Line'First + 1) = '[' then
                           raise Argument_Error with "malformed configuration section";
                        end if;
                        declare
                           Rest : constant String :=
                             Ada.Strings.Fixed.Trim (Line (Close + 1 .. Line'Last), Ada.Strings.Both);
                           Name : constant String := Line (Line'First + 1 .. Close - 1);
                        begin
                           if Rest /= "" and then Rest (Rest'First) /= '#' then
                              raise Argument_Error with "malformed configuration section";
                           elsif not Known_Section (Name) then
                              raise Argument_Error with "unknown configuration section: " & Name;
                           end if;
                           Mark_Section (Name);
                           Current_Section := To_Unbounded_String (Name);
                        end;
                     end;
                  else
                     declare
                        Equals : constant Natural := Ada.Strings.Fixed.Index (Line, "=");
                     begin
                        if Equals = 0 then
                           raise Argument_Error with "malformed configuration entry";
                        end if;
                        declare
                           Key : constant String :=
                             Ada.Strings.Fixed.Trim (Line (Line'First .. Equals - 1), Ada.Strings.Both);
                           Id  : constant Setting_Id := Setting_Of (To_String (Current_Section), Key);
                        begin
                           if Present (Id) then
                              raise Argument_Error with "duplicate configuration setting: " & Qualified (Id);
                           end if;
                           Entries (Id) := To_Unbounded_String (Line);
                           Present (Id) := True;
                        end;
                     end;
                  end if;
               end;
            end;
            Start := Stop + 1;
         end;
      end loop;
   end Parse;

   function String_Setting
     (Id      : Setting_Id;
      Entries : Entry_Array;
      Present : Presence_Array) return String is
      Line   : constant String := (if Present (Id) then To_String (Entries (Id)) else "");
      Result : UString;

      procedure Append_Character (Value : Character) is
      begin
         if (Character'Pos (Value) < 32 and then Value /= ASCII.HT) or else Character'Pos (Value) = 127 then
            raise Argument_Error with "unescaped control character in setting: " & Qualified (Id);
         end if;
         Append (Result, Value);
      end Append_Character;

      function Hex_Value (Value : Character) return Natural is
      begin
         if Value in '0' .. '9' then
            return Character'Pos (Value) - Character'Pos ('0');
         elsif Value in 'a' .. 'f' then
            return Character'Pos (Value) - Character'Pos ('a') + 10;
         elsif Value in 'A' .. 'F' then
            return Character'Pos (Value) - Character'Pos ('A') + 10;
         end if;
         raise Argument_Error with "malformed string setting: " & Qualified (Id);
      end Hex_Value;

      procedure Append_UTF8 (Code : Natural) is
      begin
         if Code <= 16#7F# then
            Append (Result, Character'Val (Code));
         elsif Code <= 16#7FF# then
            Append (Result, Character'Val (16#C0# + Code / 64));
            Append (Result, Character'Val (16#80# + Code mod 64));
         elsif Code in 16#D800# .. 16#DFFF# or else Code > 16#10FFFF# then
            raise Argument_Error with "malformed string setting: " & Qualified (Id);
         elsif Code <= 16#FFFF# then
            Append (Result, Character'Val (16#E0# + Code / 4_096));
            Append (Result, Character'Val (16#80# + Code / 64 mod 64));
            Append (Result, Character'Val (16#80# + Code mod 64));
         else
            Append (Result, Character'Val (16#F0# + Code / 262_144));
            Append (Result, Character'Val (16#80# + Code / 4_096 mod 64));
            Append (Result, Character'Val (16#80# + Code / 64 mod 64));
            Append (Result, Character'Val (16#80# + Code mod 64));
         end if;
      end Append_UTF8;
   begin
      if Line = "" then
         return Default_String (Id);
      end if;
      declare
         Equals : constant Natural := Ada.Strings.Fixed.Index (Line, "=");
         Text   : constant String :=
           (if Equals = 0 then ""
            else Ada.Strings.Fixed.Trim (Line (Equals + 1 .. Line'Last), Ada.Strings.Both));
      begin
         if Text'Length < 2 or else Text (Text'First) not in '"' | ''' then
            raise Argument_Error with "malformed string setting: " & Qualified (Id);
         end if;
         declare
            Quote  : constant Character := Text (Text'First);
            Cursor : Natural := Text'First + 1;
            Closed : Boolean := False;
         begin
            while Cursor <= Text'Last and then not Closed loop
               if Text (Cursor) = Quote then
                  Closed := True;
                  Cursor := Cursor + 1;
               elsif Quote = ''' or else Text (Cursor) /= '\' then
                  Append_Character (Text (Cursor));
                  Cursor := Cursor + 1;
               elsif Cursor = Text'Last then
                  raise Argument_Error with "malformed string setting: " & Qualified (Id);
               else
                  case Text (Cursor + 1) is
                     when 'b' => Append (Result, ASCII.BS); Cursor := Cursor + 2;
                     when 't' => Append (Result, ASCII.HT); Cursor := Cursor + 2;
                     when 'n' => Append (Result, ASCII.LF); Cursor := Cursor + 2;
                     when 'f' => Append (Result, ASCII.FF); Cursor := Cursor + 2;
                     when 'r' => Append (Result, ASCII.CR); Cursor := Cursor + 2;
                     when '"' => Append (Result, '"'); Cursor := Cursor + 2;
                     when '\' => Append (Result, '\'); Cursor := Cursor + 2;
                     when 'u' | 'U' =>
                        declare
                           Digit_Count : constant Positive := (if Text (Cursor + 1) = 'u' then 4 else 8);
                           Code        : Natural := 0;
                        begin
                           if Cursor + 1 + Digit_Count > Text'Last then
                              raise Argument_Error with "malformed string setting: " & Qualified (Id);
                           end if;
                           for Offset in 1 .. Digit_Count loop
                              declare
                                 Digit : constant Natural := Hex_Value (Text (Cursor + 1 + Offset));
                              begin
                                 if Code > (16#10FFFF# - Digit) / 16 then
                                    raise Argument_Error with "malformed string setting: " & Qualified (Id);
                                 end if;
                                 Code := Code * 16 + Digit;
                              end;
                           end loop;
                           Append_UTF8 (Code);
                           Cursor := Cursor + 2 + Digit_Count;
                        end;
                     when others =>
                        raise Argument_Error with "malformed string setting: " & Qualified (Id);
                  end case;
               end if;
            end loop;
            if not Closed then
               raise Argument_Error with "malformed string setting: " & Qualified (Id);
            end if;
            declare
               Rest : constant String := Ada.Strings.Fixed.Trim (Text (Cursor .. Text'Last), Ada.Strings.Both);
            begin
               if Rest /= "" and then Rest (Rest'First) /= '#' then
                  raise Argument_Error with "malformed string setting: " & Qualified (Id);
               end if;
            end;
         end;
      end;
      if Definitions (Id).Kind not in String_Value | Enum_Value then
         raise Argument_Error with "malformed string setting: " & Qualified (Id);
      end if;
      return To_String (Result);
   end String_Setting;

   function Escape (Text : String) return String is
      Result : UString;
   begin
      for Value of Text loop
         case Value is
            when '"' => Append (Result, '\'); Append (Result, '"');
            when '\' => Append (Result, "\\");
            when others =>
               if Character'Pos (Value) < 32 or else Character'Pos (Value) = 127 then
                  raise Argument_Error with "configuration value contains a control character";
               end if;
               Append (Result, Value);
         end case;
      end loop;
      return To_String (Result);
   end Escape;
end TOML_Codec;
