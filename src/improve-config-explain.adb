separate (Improve.Config)
function Explain (Item : Loaded_Configuration) return String is
   Result  : UString;
   Entries : Entry_Array;
   Present : Presence_Array := [others => False];
   Source  : constant String := To_String (Item.Source_Path);
begin
   if Source /= "" then
      declare
         Text : constant String := Read_Configuration (Source);
      begin
         TOML_Codec.Parse (Text, Entries, Present);
      end;
   end if;
   for Id in Setting_Id loop
      Append
        (Result,
         Qualified (Id) & " = " & Raw_Value (Item.Values, Id) & "  # source: " &
         (if Source /= "" and then Present (Id) then Source else "default") & LF);
   end loop;
   return To_String (Result);
end Explain;

