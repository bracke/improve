separate (Improve.CLI_Assets)
function Zsh_Completion return String is
   Result : Unbounded_String;
begin
   Append (Result, "#compdef improve" & LF & "local context state state_descr line" & LF);
   Append (Result, "typeset -A opt_args" & LF);
   Append (Result, "local -a improve_commands improve_value_options improve_original_words improve_option_specs" & LF);
   Append (Result, "improve_commands=()" & LF & "improve_value_options=()" & LF & "improve_option_specs=()" & LF);
   Append (Result, "improve_original_words=(""${words[@]}"")" & LF);
   for Command in Improve.CLI.Command_Kind loop
      Append (Result, "improve_commands+=(" & Improve.CLI_Metadata.Command_Name (Command) & ")" & LF);
   end loop;
   for Option in Improve.CLI_Metadata.Option_Kind loop
      if Improve.CLI_Metadata.Takes_Value (Option) then
         Append (Result, "improve_value_options+=(" & Improve.CLI_Metadata.Word (Option) & ")" & LF);
      end if;
   end loop;
   Append (Result, POSIX_Task_Status_Assignments ("improve_statuses"));
   Append
     (Result,
      "local command='' operation='' command_context='' word skip_next=0" & LF &
      "for word in $improve_original_words[2,-1]; do" & LF);
   Append (Result, "  if ((skip_next)); then skip_next=0; continue; fi" & LF);
   Append (Result, "  if [[ $word == --*=* ]]; then continue; fi" & LF);
   Append (Result, "  if (( ${improve_value_options[(Ie)$word]} )); then skip_next=1; continue; fi" & LF);
   Append
     (Result,
      "  if [[ -z $command ]] && (( ${improve_commands[(Ie)$word]} )); " &
      "then command=$word; continue; fi" & LF);
   Append (Result, "  if [[ -n $command && -z $operation && $word != --* ]]; then" & LF);
   Append
     (Result,
      "    if [[ $command == plan &&" & LF &
      "          ' " & Improve.CLI_Metadata.Positional_Values (Improve.CLI.Plan_Command) &
      " ' == *' '$word' '* ]]; then" & LF & "      operation=$word" & LF);
   Append
     (Result,
      "    elif [[ $command == audit ]]; then" & LF & "      if [[ $word == verify ]]; then" & LF &
      "        operation=verify" & LF & "      else" & LF & "        operation=export" & LF & "      fi" & LF);
   Append (Result, "    fi" & LF & "  fi" & LF);
   Append
     (Result,
      "done" & LF & "command_context=$command" & LF &
      "if [[ -n $operation ]]; then command_context=$command:$operation; fi" & LF);
   Append
     (Result,
      "_improve_context_allowed() {" & LF & "  local expected" & LF &
      "  [[ -z $command ]] && return 0" & LF & "  for expected in $@; do" & LF &
      "    [[ $command_context == $expected ]] && return 0" & LF & "  done" & LF &
      "  return 1" & LF & "}" & LF);
   for Option in Improve.CLI_Metadata.Option_Kind loop
      declare
         Word        : constant String := Improve.CLI_Metadata.Word (Option);
         Description : constant String := Improve.CLI_Metadata.Completion_Description (Option);
         Values      : constant String := Improve.CLI_Metadata.Completion_Values (Option);
         Action      : Unbounded_String;
      begin
         if Option = Improve.CLI_Metadata.Status_Option then
            Action := To_Unbounded_String (":status:($improve_statuses)");
         elsif Improve.CLI_Metadata.File_Value (Option) then
            Action := To_Unbounded_String (":file:_files");
         elsif Values /= "" then
            Action := To_Unbounded_String (":value:(" & Values & ")");
         elsif Improve.CLI_Metadata.Takes_Value (Option) then
            Action := To_Unbounded_String (":value:");
         end if;
         if not Accepted_By_Every_Command (Option) then
            declare
               Words : constant String := Accepted_Context_Words (Option);
            begin
               if Words = "" then
                  Append (Result, "if [[ -z $command ]]; then" & LF & "  ");
               else
                  Append (Result, "if _improve_context_allowed \" & LF);
                  declare
                     First : Positive := Words'First;
                  begin
                     for Index in Words'Range loop
                        if Words (Index) = ' ' then
                           Append (Result, "  " & Words (First .. Index - 1) & " \" & LF);
                           First := Index + 1;
                        end if;
                     end loop;
                     Append (Result, "  " & Words (First .. Words'Last) & "; then" & LF & "  ");
                  end;
               end if;
            end;
         end if;
         Append
           (Result,
            "improve_option_specs+=('" & Word & "[" & Description & "]" & To_String (Action) & "')" & LF);
         if not Accepted_By_Every_Command (Option) then Append (Result, "fi" & LF); end if;
      end;
   end loop;
   Append (Result, "_arguments -C \" & LF);
   Append (Result, "  ""1:command:($improve_commands)"" \" & LF);
   Append (Result, "  $improve_option_specs \" & LF);
   Append (Result, "  '*::argument:->arguments'" & LF);
   Append (Result, "if [[ $state == arguments ]]; then" & LF);
   Append (Result, "  case ""$command"" in" & LF);
   for Command in Improve.CLI.Command_Kind loop
      declare
         Values : constant String := Improve.CLI_Metadata.Positional_Values (Command);
         Words  : constant String :=
           (if Command = Improve.CLI.Help_Command then "$improve_commands" else Values);
      begin
         if Values /= "" then
            Append
              (Result,
               "    " & Improve.CLI_Metadata.Command_Name (Command) & ") _values 'argument' " & Words & " ;;" & LF);
         end if;
      end;
   end loop;
   Append (Result, "  esac" & LF & "fi" & LF);
   return To_String (Result);
end Zsh_Completion;
