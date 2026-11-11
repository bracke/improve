with Ada.Calendar.Formatting;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Unbounded;

package body Improve.Storage_Codec is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Ada.Containers.Count_Type;

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

   function Encode (Text : String) return Wide_Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Text));

   function Decode (Text : Wide_Wide_String) return String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode (Text));

   function WW (Text : String) return Unbounded_Wide_Wide_String is
     (To_Unbounded_Wide_Wide_String (Encode (Text)));

   function S (Text : Unbounded_Wide_Wide_String) return String is
     (Decode (To_Wide_Wide_String (Text)));

   function Escape (Text : String) return String is
      Result : Unbounded_String;
   begin
      for C of Text loop
         case C is
            when '\' => Append (Result, "\\");
            when LF => Append (Result, "\n");
            when CR => Append (Result, "\r");
            when others => Append (Result, C);
         end case;
      end loop;
      return To_String (Result);
   end Escape;

   function Unescape (Text : String) return String is
      Result : Unbounded_String;
      Index  : Natural := Text'First;
   begin
      while Index <= Text'Last loop
         if Text (Index) = '\' then
            if Index = Text'Last then
               raise Data_Error with "invalid persisted escape sequence";
            end if;
            case Text (Index + 1) is
               when '\' => Append (Result, '\');
               when 'n' => Append (Result, LF);
               when 'r' => Append (Result, CR);
               when others => raise Data_Error with "invalid persisted escape sequence";
            end case;
            Index := Index + 2;
         else
            Append (Result, Text (Index));
            Index := Index + 1;
         end if;
      end loop;
      return To_String (Result);
   end Unescape;

   function Field (Payload, Name : String) return String is
      Prefix : constant String := Name & "=";
      Start  : Natural := Payload'First;
   begin
      while Start <= Payload'Last loop
         declare
            Stop : Natural := Start;
         begin
            while Stop <= Payload'Last and then Payload (Stop) /= LF loop
               Stop := Stop + 1;
            end loop;
            if Stop - Start >= Prefix'Length and then
              Payload (Start .. Start + Prefix'Length - 1) = Prefix
            then
               return Unescape (Payload (Start + Prefix'Length .. Stop - 1));
            end if;
            Start := Stop + 1;
         end;
      end loop;
      raise Data_Error with "missing persisted field " & Name;
   end Field;

   function Has_Field (Payload, Name : String) return Boolean is
      Prefix : constant String := Name & "=";
      Start  : Natural := Payload'First;
   begin
      while Start <= Payload'Last loop
         declare
            Stop : Natural := Start;
         begin
            while Stop <= Payload'Last and then Payload (Stop) /= LF loop
               Stop := Stop + 1;
            end loop;
            if Stop - Start >= Prefix'Length and then
              Payload (Start .. Start + Prefix'Length - 1) = Prefix
            then
               return True;
            end if;
            Start := Stop + 1;
         end;
      end loop;
      return False;
   end Has_Field;

   function Field_Or (Payload, Name, Default : String) return String is
     (if Has_Field (Payload, Name) then Field (Payload, Name) else Default);

   function Pair (Name, Value : String) return String is (Name & "=" & Escape (Value));

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Boolean_Image (Value : Boolean) return String is (if Value then "true" else "false");

   function Pack (Values : Improve.Model.UString_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      for Value of Values loop
         declare
            Text : constant String := To_String (Value);
         begin
            Append (Result, Number (Text'Length) & ":" & Text);
         end;
      end loop;
      return To_String (Result);
   end Pack;

   function Unpack
     (Text          : String;
      Maximum_Items : Natural := 10_000;
      Maximum_Bytes : Natural := 1_048_576) return Improve.Model.UString_Vectors.Vector is
      Result : Improve.Model.UString_Vectors.Vector;
      Index  : Natural := Text'First;
   begin
      if Text'Length > Maximum_Bytes then
         raise Data_Error with "persisted list exceeds configured byte limit";
      end if;
      while Index <= Text'Last loop
         if Result.Length >= Ada.Containers.Count_Type (Maximum_Items) then
            raise Data_Error with "persisted list exceeds configured item limit";
         end if;
         declare
            Colon : Natural := Index;
         begin
            while Colon <= Text'Last and then Text (Colon) /= ':' loop
               if Text (Colon) not in '0' .. '9' then
                  raise Data_Error with "invalid persisted list";
               end if;
               Colon := Colon + 1;
            end loop;
            if Colon > Text'Last or else Colon = Index then
               raise Data_Error with "invalid persisted list";
            end if;
            declare
               Length : constant Natural := Natural'Value (Text (Index .. Colon - 1));
               First  : constant Natural := Colon + 1;
               Last   : constant Natural := Colon + Length;
            begin
               if Last > Text'Last then
                  raise Data_Error with "truncated persisted list";
               end if;
               Result.Append (To_Unbounded_String (Text (First .. Last)));
               Index := Last + 1;
            end;
         end;
      end loop;
      return Result;
   exception
      when Constraint_Error => raise Data_Error with "invalid persisted list length";
   end Unpack;

   function Timestamp (Value : Ada.Calendar.Time) return String is
     (Ada.Calendar.Formatting.Image (Value, Include_Time_Fraction => False, Time_Zone => 0));

   function Parse_Time (Text : String) return Ada.Calendar.Time is
     (Ada.Calendar.Formatting.Value (Text, Time_Zone => 0));

   function Id_Image (Prefix : String; Id : Positive) return String is
      Value_Text : constant String := Number (Id);
   begin
      return Prefix & [1 .. Integer'Max (0, 6 - Value_Text'Length) => '0'] & Value_Text;
   end Id_Image;

   function Plan_Row_Id (Plan_Id : String) return Positive is
   begin
      if Plan_Id'Length /= 11 or else Plan_Id (Plan_Id'First .. Plan_Id'First + 4) /= "PLAN-" then
         raise Argument_Error with "invalid plan identity " & Plan_Id;
      end if;
      return Positive'Value (Plan_Id (Plan_Id'First + 5 .. Plan_Id'Last));
   exception
      when Constraint_Error => raise Argument_Error with "invalid plan identity " & Plan_Id;
   end Plan_Row_Id;
end Improve.Storage_Codec;
