separate (Improve.CLI)
function Help_Text return String is
   Result : Unbounded_String;

   procedure Line (Left, Key : String; Width : Positive := 28) is
   begin
      Append (Result, "  " & Left & [1 .. Integer'Max (1, Width - Left'Length) => ' '] & Message (Key) & LF);
   end Line;
begin
   Append (Result, Message ("help.usage") & LF & LF & Message ("help.commands") & LF);
   for Command in Command_Kind loop
      Line (Improve.CLI_Metadata.Command_Name (Command), Improve.CLI_Metadata.Command_Help_Key (Command));
   end loop;
   Append (Result, LF & Message ("help.options") & LF);
   for Option in Improve.CLI_Metadata.Option_Kind loop
      if Improve.CLI_Metadata.Document_In_Help (Option) then
         Line (Improve.CLI_Metadata.Help_Display (Option), Improve.CLI_Metadata.Help_Key (Option), 36);
      end if;
   end loop;
   Append (Result, LF & Message ("help.exit") & LF);
   return To_String (Result);
end Help_Text;
