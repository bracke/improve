set -l improve_commands projects findings plan audit apply tasks status refresh verify recover doctor
set -a improve_commands config completion manpage help version
complete -c improve -f -n '__fish_use_subcommand' -a "$improve_commands"
complete -c improve -f -n '__fish_seen_subcommand_from plan' -a 'list show approve diff explain'
complete -c improve -f -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish'
complete -c improve -l format -a 'terminal json markdown'
complete -c improve -l color -a 'auto always never'
complete -c improve -l severity -a 'critical high medium low info'
complete -c improve -l status -a 'all planned ready running blocked completed failed stale'
complete -c improve -l config -r -F
complete -c improve -l database -r -F
complete -c improve -l state -r -F
complete -c improve -l path -r -F
