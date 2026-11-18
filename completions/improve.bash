_improve_complete() {
  local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}
  local command=${COMP_WORDS[1]}
  local commands='projects findings plan audit apply tasks status refresh verify recover doctor'
  commands="$commands config completion manpage"
  local options='--config --database --state --project --format --color --run --revision --against-revision --task'
  options="$options --status --indicator --severity --path --dry-run --all --verbose --quiet --help"
  local words="$commands help version $options"
  case "$prev" in
    --format) words='terminal json markdown' ;;
    --color) words='auto always never' ;;
    --severity) words='critical high medium low info' ;;
    --status) words='all planned ready running blocked completed failed stale' ;;
    completion) words='bash zsh fish' ;;
    --config|--database|--state|--path) COMPREPLY=($(compgen -f -- "$cur")); return ;;
    *) if [[ "$command" == plan ]]; then words="list show approve diff explain $options"; fi ;;
  esac
  COMPREPLY=($(compgen -W "$words" -- "$cur"))
}
complete -F _improve_complete improve
