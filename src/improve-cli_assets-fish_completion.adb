separate (Improve.CLI_Assets)
function Fish_Completion return String is
   Result : Unbounded_String;
begin
   Append (Result, "set -l improve_commands" & LF);
   for Command in Improve.CLI.Command_Kind loop
      Append (Result, "set -a improve_commands " & Improve.CLI_Metadata.Command_Name (Command) & LF);
   end loop;
   Append (Result, Fish_Task_Status_Assignments);
   Append (Result, "function __improve_command_state --argument-names expected" & LF);
   Append (Result, "    set -l skip_next 0" & LF);
   Append (Result, "    for token in (commandline -opc)[2..-1]" & LF);
   Append (Result, "        if test $skip_next -eq 1" & LF);
   Append (Result, "            set skip_next 0" & LF & "            continue" & LF & "        end" & LF);
   Append (Result, "        switch $token" & LF & "            case '--*=*'" & LF & "                continue" & LF);
   for Option in Improve.CLI_Metadata.Option_Kind loop
      if Improve.CLI_Metadata.Takes_Value (Option) then
         Append
           (Result,
            "            case '" & Improve.CLI_Metadata.Word (Option) & "'" & LF &
            "                set skip_next 1" & LF & "                continue" & LF);
      end if;
   end loop;
   for Command in Improve.CLI.Command_Kind loop
      Append
        (Result,
         "            case '" & Improve.CLI_Metadata.Command_Name (Command) & "'" & LF &
         "                test -n ""$expected""; and test ""$token"" = ""$expected""" & LF &
         "                return" & LF);
   end loop;
   Append
     (Result,
      "        end" & LF & "    end" & LF &
      "    test $skip_next -eq 0; and test -z ""$expected""" & LF & "end" & LF);
   Append (Result, "function __improve_option_state" & LF);
   Append (Result, "    set -l command ''" & LF & "    set -l operation ''" & LF);
   Append (Result, "    set -l skip_next 0" & LF);
   Append (Result, "    for token in (commandline -opc)[2..-1]" & LF);
   Append (Result, "        if test $skip_next -eq 1" & LF);
   Append (Result, "            set skip_next 0" & LF & "            continue" & LF & "        end" & LF);
   Append (Result, "        switch $token" & LF & "            case '--*=*'" & LF & "                continue" & LF);
   for Option in Improve.CLI_Metadata.Option_Kind loop
      if Improve.CLI_Metadata.Takes_Value (Option) then
         Append
           (Result,
            "            case '" & Improve.CLI_Metadata.Word (Option) & "'" & LF &
            "                set skip_next 1" & LF & "                continue" & LF);
      end if;
   end loop;
   Append (Result, "            case '--*'" & LF & "                continue" & LF & "        end" & LF);
   Append (Result, "        if test -z ""$command""" & LF & "            switch $token" & LF);
   for Command in Improve.CLI.Command_Kind loop
      Append
        (Result,
         "                case '" & Improve.CLI_Metadata.Command_Name (Command) & "'" & LF &
         "                    set command $token" & LF & "                    continue" & LF);
   end loop;
   Append (Result, "            end" & LF & "        else if test -z ""$operation""" & LF);
   Append (Result, "            if test ""$command"" = plan" & LF & "                switch $token" & LF);
   for Action in Improve.CLI.Plan_Operation'Succ (Improve.CLI.Create_Plan) .. Improve.CLI.Plan_Operation'Last loop
      Append
        (Result,
         "                    case '" & Improve.CLI_Metadata.Plan_Operation_Name (Action) & "'" & LF &
         "                        set operation $token" & LF);
   end loop;
   Append
     (Result,
      "                end" & LF & "            else if test ""$command"" = audit" & LF &
      "                if test ""$token"" = verify" & LF & "                    set operation verify" & LF &
      "                else" & LF & "                    set operation export" & LF & "                end" & LF &
      "            end" & LF & "        end" & LF & "    end" & LF);
   Append (Result, "    test -z ""$command""; and return 0" & LF);
   Append (Result, "    set -l context $command" & LF);
   Append (Result, "    test -n ""$operation""; and set context $command:$operation" & LF);
   Append (Result, "    set -l option $argv[1]" & LF & "    switch $option:$context" & LF);
   for Option in Improve.CLI_Metadata.Option_Kind loop
      if not Accepted_By_Every_Command (Option) then
         declare
            Full_Name : constant String := Improve.CLI_Metadata.Word (Option);
            Name      : constant String := Full_Name (Full_Name'First + 2 .. Full_Name'Last);
         begin
            for Command in Improve.CLI.Command_Kind loop
               if Improve.CLI_Metadata.Accepted_By_Command (Option, Command) then
                  Append
                    (Result,
                     "        case '" & Name & ":" & Improve.CLI_Metadata.Command_Name (Command) & "'" & LF &
                     "            return 0" & LF);
               end if;
            end loop;
            for Context in Improve.CLI_Metadata.Operation_Context loop
               if Context /= Improve.CLI_Metadata.No_Operation then
                  declare
                     Command : constant Improve.CLI.Command_Kind := Improve.CLI_Metadata.Context_Command (Context);
                  begin
                     if Improve.CLI_Metadata.Accepted_In_Context (Option, Command, Context) then
                        Append
                          (Result,
                           "        case '" & Name & ":" & Improve.CLI_Metadata.Command_Name (Command) & ":" &
                           Improve.CLI_Metadata.Context_Name (Context) & "'" & LF &
                           "            return 0" & LF);
                     end if;
                  end;
               end if;
            end loop;
         end;
      end if;
   end loop;
   Append (Result, "    end" & LF & "    return 1" & LF & "end" & LF);
   Append (Result, "complete -c improve -f -n '__improve_command_state' -a ""$improve_commands""" & LF);
   for Command in Improve.CLI.Command_Kind loop
      declare
         Values : constant String := Improve.CLI_Metadata.Positional_Values (Command);
         Words  : constant String :=
           (if Command = Improve.CLI.Help_Command then """$improve_commands""" else "'" & Values & "'");
      begin
         if Values /= "" then
            Append
              (Result,
               "complete -c improve -f -n '__improve_command_state " &
               Improve.CLI_Metadata.Command_Name (Command) & "' -a " & Words & LF);
         end if;
      end;
   end loop;
   for Option in Improve.CLI_Metadata.Option_Kind loop
      declare
         Full_Name : constant String := Improve.CLI_Metadata.Word (Option);
         Name      : constant String := Full_Name (Full_Name'First + 2 .. Full_Name'Last);
         Values    : constant String := Improve.CLI_Metadata.Completion_Values (Option);
      begin
         Append (Result, "complete -c improve -l " & Name);
         if not Accepted_By_Every_Command (Option) then
            Append (Result, " -n '__improve_option_state " & Name & "'");
         end if;
         if Improve.CLI_Metadata.Takes_Value (Option) then Append (Result, " -r"); end if;
         if Improve.CLI_Metadata.File_Value (Option) then
            Append (Result, " -F");
         elsif Option = Improve.CLI_Metadata.Status_Option then
            Append (Result, " -a ""$improve_statuses""");
         elsif Values /= "" then
            Append (Result, " -a '" & Values & "'");
         end if;
         Append (Result, LF);
      end;
   end loop;
   return To_String (Result);
end Fish_Completion;
