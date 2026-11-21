separate (Improve.Config)
function Image (Item : Settings) return String is
   Result       : UString;
   Last_Section : UString;
begin
   Validate_Operational_Text
     ("quality.database", To_String (Item.Quality_Database), Maximum_Length => 4_096);
   Validate_Operational_Text ("workflow.task_kind", To_String (Item.Task_Kind), Maximum_Length => 128);
   for Id in Setting_Id loop
      declare
         Definition : Setting_Descriptor renames Definitions (Id);
         Section    : constant String := To_String (Definition.Section);
         Raw        : constant String := Raw_Value (Item, Id);
         Rendered   : constant String :=
           (if Definition.Kind in String_Value | Enum_Value then '"' & TOML_Codec.Escape (Raw) & '"' else Raw);
      begin
         if Section /= To_String (Last_Section) then
            Append (Result, "[" & Section & "]" & LF);
            Last_Section := Definition.Section;
         end if;
         Append (Result, To_String (Definition.Name) & " = " & Rendered & LF);
      end;
   end loop;
   return To_String (Result);
end Image;

