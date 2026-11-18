package body Improve.CLI_Assets is
   LF : constant Character := Character'Val (10);
   Commands : constant String :=
     "projects findings plan audit apply tasks status refresh verify recover doctor config completion " &
     "manpage help version";
   Options : constant String :=
     "--config --database --state --project --format --color --run --revision --against-revision --task " &
     "--status --indicator --severity --path --limit --cursor --signing-key --release --dry-run --all " &
     "--verbose --quiet --help";

   function Completion (Shell : String) return String is
   begin
      if Shell = "bash" then
         return
           "_improve_complete() {" & LF &
           "  local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}" & LF &
           "  local command=${COMP_WORDS[1]} words='" & Commands & " " & Options & "'" & LF &
           "  case $prev in" & LF &
           "    --format) words='terminal json markdown dot' ;;" & LF &
           "    --color) words='auto always never' ;;" & LF &
           "    --severity) words='critical high medium low info' ;;" & LF &
           "    --status) words='all planned ready running blocked completed failed stale' ;;" & LF &
           "    completion) words='bash zsh fish' ;;" & LF &
           "    --config|--database|--state|--path|--signing-key) " &
           "COMPREPLY=($(compgen -f -- ""$cur"")); return ;;" & LF &
           "    *) if [[ $command == plan ]]; then words='list show approve diff explain graph " &
           Options & "'; fi ;;" & LF &
           "  esac" & LF &
           "  COMPREPLY=($(compgen -W ""$words"" -- ""$cur""))" & LF &
           "}" & LF & "complete -F _improve_complete improve" & LF;
      elsif Shell = "zsh" then
         return
           "#compdef improve" & LF &
           "_arguments '1:command:(" & Commands & ")' " &
           "'2:operation:(list show approve diff explain graph verify bash zsh fish)' " &
           "'--format[output format]:(terminal json markdown dot)' " &
           "'--color[color policy]:(auto always never)' " &
           "'--severity[finding severity]:(critical high medium low info)' " &
           "'--status[task status]:(all planned ready running blocked completed failed stale)' " &
           "'--config[configuration file]:file:_files' '--database[quality database]:file:_files' " &
           "'--state[Improve state]:file:_files' '*:argument:'" & LF;
      elsif Shell = "fish" then
         return
           "complete -c improve -f -n '__fish_use_subcommand' -a '" & Commands & "'" & LF &
           "complete -c improve -f -n '__fish_seen_subcommand_from plan' " &
           "-a 'list show approve diff explain graph'" & LF &
           "complete -c improve -f -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish'" & LF &
           "complete -c improve -l format -a 'terminal json markdown dot'" & LF &
           "complete -c improve -l color -a 'auto always never'" & LF &
           "complete -c improve -l severity -a 'critical high medium low info'" & LF &
           "complete -c improve -l status -a 'all planned ready running blocked completed failed stale'" & LF &
           "complete -c improve -l config -r -F; complete -c improve -l database -r -F" & LF &
           "complete -c improve -l state -r -F; complete -c improve -l path -r -F" & LF;
      end if;
      raise Argument_Error with "unsupported completion shell " & Shell;
   end Completion;

   function Manpage return String is
   begin
      return
        ".TH IMPROVE 1 """" ""Improve 0.1.0"" ""User Commands""" & LF &
        ".SH NAME" & LF & "improve \- deterministic Ada quality remediation planning" & LF &
        ".SH SYNOPSIS" & LF & ".B improve" & LF & "command [options]" & LF &
        ".SH DESCRIPTION" & LF &
        "Improve reads completed Ada Quality assessments, stores immutable remediation plans, and publishes " &
        "approved work as native model_runner tasks." & LF &
        ".SH COMMANDS" & LF &
        "projects, findings, plan, audit, apply, tasks, status, refresh, verify, recover, doctor, config, " &
        "completion, " &
        "manpage, help, and version." & LF &
        ".SH PLAN OPERATIONS" & LF &
        "plan supports list, show, approve, diff, explain, and graph in addition to deterministic generation." & LF &
        ".SH AUDIT" & LF &
        "audit PLAN-ID [--revision N] exports immutable provenance, approval, publication, and " &
        "verification evidence; audit verify FILE checks its digest and optional Ed25519 signature." & LF &
        ".SH OUTPUT" & LF &
        "--format accepts terminal, json, markdown, or dot for plan graph. JSON output and errors are single " &
        "versioned documents." & LF &
        ".SH EXIT STATUS" & LF &
        "0 success; 1 unresolved verification or unhealthy diagnostics; 2 invalid input; " &
        "3 unavailable evidence; 4 storage or internal failure." & LF &
        ".SH SEE ALSO" & LF & "ada_quality(1), model_runner(1)" & LF;
   end Manpage;
end Improve.CLI_Assets;
