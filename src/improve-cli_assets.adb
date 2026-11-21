with Ada.Strings.Unbounded;
with Improve.CLI;
with Improve.CLI_Metadata;
with Improve.Tasks;

package body Improve.CLI_Assets is
   use Ada.Strings.Unbounded;
   use type Improve.CLI.Command_Kind;
   use type Improve.CLI_Metadata.Operation_Context;
   use type Improve.CLI_Metadata.Option_Kind;

   LF : constant Character := Character'Val (10);

   function Prose_List (Values : String) return String is
      Result     : Unbounded_String;
      Word_Start : Positive := Values'First;
      Word_Count : Natural := 0;
   begin
      if Values = "" then return ""; end if;
      for Item of Values loop
         if Item = ' ' then Word_Count := Word_Count + 1; end if;
      end loop;
      Word_Count := Word_Count + 1;
      declare
         Current : Natural := 0;
      begin
         for Index in Values'Range loop
            if Values (Index) = ' ' then
               Current := Current + 1;
               Append (Result, Values (Word_Start .. Index - 1));
               Append (Result, (if Current = Word_Count - 1 then ", or " else ", "));
               Word_Start := Index + 1;
            end if;
         end loop;
      end;
      Append (Result, Values (Word_Start .. Values'Last));
      return To_String (Result);
   end Prose_List;

   function POSIX_Task_Status_Assignments (Variable : String) return String is
      Result : Unbounded_String :=
        To_Unbounded_String ("  local " & Variable & "='all unresolved'" & LF);
   begin
      for Status in Improve.Tasks.Operational_Status loop
         Append
           (Result,
            "  " & Variable & "=""$" & Variable & " " & Improve.Tasks.Image (Status) & """" & LF);
      end loop;
      return To_String (Result);
   end POSIX_Task_Status_Assignments;

   function Fish_Task_Status_Assignments return String is
      Result : Unbounded_String := To_Unbounded_String ("set -l improve_statuses 'all unresolved'" & LF);
   begin
      for Status in Improve.Tasks.Operational_Status loop
         Append
           (Result,
            "set improve_statuses ""$improve_statuses " & Improve.Tasks.Image (Status) & """" & LF);
      end loop;
      return To_String (Result);
   end Fish_Task_Status_Assignments;

   function Accepted_By_Every_Command (Option : Improve.CLI_Metadata.Option_Kind) return Boolean is
     (for all Command in Improve.CLI.Command_Kind =>
        Improve.CLI_Metadata.Accepted_By_Command (Option, Command));

   function Accepted_Context_Words (Option : Improve.CLI_Metadata.Option_Kind) return String is
      Result : Unbounded_String;

      procedure Add (Value : String) is
      begin
         if Length (Result) > 0 then
            Append (Result, ' ');
         end if;
         Append (Result, Value);
      end Add;
   begin
      for Command in Improve.CLI.Command_Kind loop
         if Improve.CLI_Metadata.Accepted_By_Command (Option, Command) then
            Add (Improve.CLI_Metadata.Command_Name (Command));
         end if;
      end loop;
      for Context in Improve.CLI_Metadata.Operation_Context loop
         if Context /= Improve.CLI_Metadata.No_Operation then
            declare
               Command : constant Improve.CLI.Command_Kind := Improve.CLI_Metadata.Context_Command (Context);
            begin
               if Improve.CLI_Metadata.Accepted_In_Context (Option, Command, Context) then
                  Add
                    (Improve.CLI_Metadata.Command_Name (Command) & ":" &
                     Improve.CLI_Metadata.Context_Name (Context));
               end if;
            end;
         end if;
      end loop;
      return To_String (Result);
   end Accepted_Context_Words;

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

   function Zsh_Completion return String is
      Result : Unbounded_String;
   begin
      Append (Result, "#compdef improve" & LF & "local context state state_descr line" & LF);
      Append (Result, "typeset -A opt_args" & LF);
      Append
        (Result,
         "local -a improve_commands improve_value_options improve_original_words improve_option_specs" & LF);
      Append
        (Result,
         "improve_commands=()" & LF & "improve_value_options=()" & LF & "improve_option_specs=()" & LF);
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
      Append
        (Result, "  if (( ${improve_value_options[(Ie)$word]} )); then skip_next=1; continue; fi" & LF);
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
            if not Accepted_By_Every_Command (Option) then
               Append (Result, "fi" & LF);
            end if;
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
                  "    " & Improve.CLI_Metadata.Command_Name (Command) & ") _values 'argument' " & Words & " ;;" &
                  LF);
            end if;
         end;
      end loop;
      Append (Result, "  esac" & LF & "fi" & LF);
      return To_String (Result);
   end Zsh_Completion;

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
                        Command : constant Improve.CLI.Command_Kind :=
                          Improve.CLI_Metadata.Context_Command (Context);
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
            if Improve.CLI_Metadata.Takes_Value (Option) then
               Append (Result, " -r");
            end if;
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

   function Completion (Shell : String) return String is
     (if Shell = "bash" then Bash_Completion
      elsif Shell = "zsh" then Zsh_Completion
      elsif Shell = "fish" then Fish_Completion
      else raise Argument_Error with "unsupported completion shell " & Shell);

   function Manpage return String is
   begin
      return
        ".TH IMPROVE 1 """" ""Improve 0.1.0"" ""User Commands""" & LF &
        ".SH NAME" & LF & "improve \- deterministic Ada quality remediation planning" & LF &
        ".SH SYNOPSIS" & LF & ".B improve" & LF & "command [options]" & LF &
        ".SH DESCRIPTION" & LF &
        "Improve reads completed Ada Quality assessments, stores immutable remediation plans, and publishes" & LF &
        "native model_runner tasks." & LF &
        ".SH COMMANDS" & LF & Improve.CLI_Metadata.Command_List & "." & LF &
        ".SH PLAN OPERATIONS" & LF &
        "plan supports " & Prose_List (Improve.CLI_Metadata.Plan_Operation_Words) &
        " in addition to deterministic generation." & LF &
        ".SH AUDIT" & LF &
        "audit PLAN-ID [--revision N] exports immutable provenance, approval, publication, and verification evidence." &
        LF &
        "audit verify FILE checks its canonical digest. Signed artifacts require --verification-key FILE as an " &
        "independent" & LF &
        "trust anchor for the Ed25519 signature." & LF &
        ".SH OUTPUT" & LF &
        "--format accepts " & Prose_List (Improve.CLI_Metadata.Completion_Values (Improve.CLI_Metadata.Format_Option)) &
        " for plan graph. JSON output and JSON errors are single " &
        "versioned" & LF &
        "documents." & LF &
        ".SH LOCAL REFINEMENT" & LF &
        "--agent-model, --agent-model-path, and --agent-model-sha256 override the optional local runtime. --no-agent " &
        "disables" & LF &
        "refinement for one invocation. --progress accepts " &
        Prose_List (Improve.CLI_Metadata.Completion_Values (Improve.CLI_Metadata.Progress_Option)) &
        "; auto emits runtime progress only " &
        "when" & LF &
        "standard error is a terminal." & LF &
        ".SH EXIT STATUS" & LF &
        "0 success; 1 unresolved verification or unhealthy diagnostics; 2 invalid input; 3 unavailable evidence; 4 " &
        "storage or" & LF &
        "internal failure; 130 interrupted." & LF &
        ".SH SEE ALSO" & LF & "ada_quality(1), model_runner(1)" & LF;
   end Manpage;
end Improve.CLI_Assets;
