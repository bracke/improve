separate (Improve.CLI_Assets)
function Bash_Completion return String is
   Result : Unbounded_String;
begin
   Append (Result, "_improve_complete() {" & LF);
   Append (Result, "  local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}" & LF);
   Append (Result, "  local inline_option='' inline_prefix=''" & LF);
   Append (Result, "  if [[ ""$cur"" == --*=* ]]; then" & LF);
   Append (Result, "    inline_option=${cur%%=*}; inline_prefix=""$inline_option=""; cur=${cur#*=}" & LF);
   Append (Result, "  fi" & LF);
   Append (Result, "  local commands='' options='' value_options=''" & LF);
   for Command in Improve.CLI.Command_Kind loop
      Append (Result, "  commands=""$commands " & Improve.CLI_Metadata.Command_Name (Command) & """" & LF);
   end loop;
   for Option in Improve.CLI_Metadata.Option_Kind loop
      Append (Result, "  options=""$options " & Improve.CLI_Metadata.Word (Option) & """" & LF);
      if Improve.CLI_Metadata.Takes_Value (Option) then
         Append (Result, "  value_options=""$value_options " & Improve.CLI_Metadata.Word (Option) & """" & LF);
      end if;
   end loop;
   Append (Result, "  local command='' operation='' word skip_next=0 i" & LF);
   Append (Result, "  for ((i=1; i<COMP_CWORD; i++)); do" & LF);
   Append (Result, "    word=${COMP_WORDS[i]}" & LF);
   Append (Result, "    if ((skip_next)); then skip_next=0; continue; fi" & LF);
   Append (Result, "    if [[ ""$word"" == --*=* ]]; then continue; fi" & LF);
   Append
     (Result, "    if [[ "" $value_options "" == *"" $word ""* ]]; then skip_next=1; continue; fi" & LF);
   Append
     (Result,
      "    if [[ -z ""$command"" && "" $commands "" == *"" $word ""* ]]; " &
      "then command=$word; continue; fi" & LF);
   Append (Result, "    if [[ -n ""$command"" && -z ""$operation"" && ""$word"" != --* ]]; then" & LF);
   Append
     (Result,
      "      if [[ ""$command"" == plan && "" " & Improve.CLI_Metadata.Positional_Values
        (Improve.CLI.Plan_Command) & " "" == *"" $word ""* ]]; then operation=$word" & LF);
   Append
     (Result,
      "      elif [[ ""$command"" == audit ]]; then " &
      "if [[ ""$word"" == verify ]]; then operation=verify; else operation=export; fi" & LF);
   Append (Result, "      fi" & LF & "    fi" & LF);
   Append (Result, "  done" & LF);
   Append (Result, POSIX_Task_Status_Assignments ("task_statuses"));
   Append (Result, "  local command_context=$command command_options=''" & LF);
   Append
     (Result,
      "  if [[ -n ""$operation"" ]]; then command_context=""$command:$operation""; fi" & LF);
   Append (Result, "  case ""$command_context"" in" & LF);
   for Command in Improve.CLI.Command_Kind loop
      Append (Result, "    " & Improve.CLI_Metadata.Command_Name (Command) & ")" & LF);
      for Option in Improve.CLI_Metadata.Option_Kind loop
         if Improve.CLI_Metadata.Accepted_By_Command (Option, Command) then
            Append
              (Result,
               "      command_options=""$command_options " & Improve.CLI_Metadata.Word (Option) & """" & LF);
         end if;
      end loop;
      Append (Result, "      ;;" & LF);
   end loop;
   for Context in Improve.CLI_Metadata.Operation_Context loop
      if Context /= Improve.CLI_Metadata.No_Operation then
         declare
            Command : constant Improve.CLI.Command_Kind := Improve.CLI_Metadata.Context_Command (Context);
         begin
            Append
              (Result,
               "    " & Improve.CLI_Metadata.Command_Name (Command) & ":" &
               Improve.CLI_Metadata.Context_Name (Context) & ")" & LF);
            for Option in Improve.CLI_Metadata.Option_Kind loop
               if Improve.CLI_Metadata.Accepted_In_Context (Option, Command, Context) then
                  Append
                    (Result,
                     "      command_options=""$command_options " & Improve.CLI_Metadata.Word (Option) & """" &
                     LF);
               end if;
            end loop;
            Append (Result, "      ;;" & LF);
         end;
      end if;
   end loop;
   Append (Result, "  esac" & LF);
   Append (Result, "  local words='' value_context=${inline_option:-$prev}" & LF);
   Append
     (Result,
      "  if [[ -z ""$command"" ]]; then words=""$commands $options""; " &
      "else words=""$command_options""; fi" & LF);
   Append
     (Result,
      "  if [[ -n ""$command"" && ""$value_context"" == --* && " &
      """ $command_options "" != *"" $value_context ""* ]]; then" & LF &
      "    COMPREPLY=()" & LF & "    return" & LF & "  fi" & LF);
   Append (Result, "  case ""$value_context"" in" & LF);
   for Option in Improve.CLI_Metadata.Option_Kind loop
      declare
         Values : constant String := Improve.CLI_Metadata.Completion_Values (Option);
      begin
         if Values /= "" then
            Append
              (Result, "    " & Improve.CLI_Metadata.Word (Option) & ") words='" & Values & "' ;;" & LF);
         elsif Improve.CLI_Metadata.File_Value (Option) then
            Append
              (Result, "    " & Improve.CLI_Metadata.Word (Option) &
               ") compopt -o filenames 2>/dev/null || true" & LF &
               "       COMPREPLY=(); while IFS= read -r word; do" & LF &
               "         COMPREPLY+=(""$inline_prefix$word"")" & LF &
               "       done < <(compgen -f -- ""$cur""); return ;;" & LF);
         end if;
      end;
   end loop;
   Append (Result, "    --status) words=""$task_statuses"" ;;" & LF);
   Append (Result, "    *) case ""$command"" in" & LF);
   for Command in Improve.CLI.Command_Kind loop
      declare
         Values : constant String := Improve.CLI_Metadata.Positional_Values (Command);
         Words : constant String :=
           (if Command = Improve.CLI.Help_Command
            then "$commands $command_options"
            else Values & " $command_options");
      begin
         if Values /= "" then
            Append
              (Result,
               "         " & Improve.CLI_Metadata.Command_Name (Command) & ") words=""" & Words &
               """ ;;" & LF);
         end if;
      end;
   end loop;
   Append (Result, "       esac ;;" & LF & "  esac" & LF);
   Append (Result, "  COMPREPLY=()" & LF);
   Append
     (Result, "  while IFS= read -r word; do COMPREPLY+=(""$inline_prefix$word""); done < <(" &
      "compgen -W ""$words"" -- ""$cur"")" & LF);
   Append (Result, "}" & LF & "complete -F _improve_complete improve" & LF);
   return To_String (Result);
end Bash_Completion;
