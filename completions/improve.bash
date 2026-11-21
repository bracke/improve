_improve_complete() {
  local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}
  local inline_option='' inline_prefix=''
  if [[ "$cur" == --*=* ]]; then
    inline_option=${cur%%=*}; inline_prefix="$inline_option="; cur=${cur#*=}
  fi
  local commands='' options='' value_options=''
  commands="$commands projects"
  commands="$commands findings"
  commands="$commands plan"
  commands="$commands audit"
  commands="$commands apply"
  commands="$commands tasks"
  commands="$commands status"
  commands="$commands refresh"
  commands="$commands verify"
  commands="$commands recover"
  commands="$commands doctor"
  commands="$commands config"
  commands="$commands completion"
  commands="$commands manpage"
  commands="$commands help"
  commands="$commands version"
  options="$options --config"
  value_options="$value_options --config"
  options="$options --database"
  value_options="$value_options --database"
  options="$options --state"
  value_options="$value_options --state"
  options="$options --project"
  value_options="$value_options --project"
  options="$options --format"
  value_options="$value_options --format"
  options="$options --color"
  value_options="$value_options --color"
  options="$options --progress"
  value_options="$value_options --progress"
  options="$options --run"
  value_options="$value_options --run"
  options="$options --revision"
  value_options="$value_options --revision"
  options="$options --against-revision"
  value_options="$value_options --against-revision"
  options="$options --task"
  value_options="$value_options --task"
  options="$options --status"
  value_options="$value_options --status"
  options="$options --indicator"
  value_options="$value_options --indicator"
  options="$options --severity"
  value_options="$value_options --severity"
  options="$options --path"
  value_options="$value_options --path"
  options="$options --limit"
  value_options="$value_options --limit"
  options="$options --cursor"
  value_options="$value_options --cursor"
  options="$options --signing-key"
  value_options="$value_options --signing-key"
  options="$options --verification-key"
  value_options="$value_options --verification-key"
  options="$options --agent-model"
  value_options="$value_options --agent-model"
  options="$options --agent-model-path"
  value_options="$value_options --agent-model-path"
  options="$options --agent-model-sha256"
  value_options="$value_options --agent-model-sha256"
  options="$options --no-agent"
  options="$options --dry-run"
  options="$options --release"
  options="$options --all"
  options="$options --verbose"
  options="$options --quiet"
  options="$options --help"
  options="$options --version"
  local command='' operation='' word skip_next=0 i
  for ((i=1; i<COMP_CWORD; i++)); do
    word=${COMP_WORDS[i]}
    if ((skip_next)); then skip_next=0; continue; fi
    if [[ "$word" == --*=* ]]; then continue; fi
    if [[ " $value_options " == *" $word "* ]]; then skip_next=1; continue; fi
    if [[ -z "$command" && " $commands " == *" $word "* ]]; then command=$word; continue; fi
    if [[ -n "$command" && -z "$operation" && "$word" != --* ]]; then
      if [[ "$command" == plan && " list show approve diff explain graph " == *" $word "* ]]; then operation=$word
      elif [[ "$command" == audit ]]; then if [[ "$word" == verify ]]; then operation=verify; else operation=export; fi
      fi
    fi
  done
  local task_statuses='all unresolved'
  task_statuses="$task_statuses proposed"
  task_statuses="$task_statuses published"
  task_statuses="$task_statuses in_progress"
  task_statuses="$task_statuses awaiting_verification"
  task_statuses="$task_statuses verified"
  task_statuses="$task_statuses blocked"
  task_statuses="$task_statuses failed"
  task_statuses="$task_statuses cancelled"
  task_statuses="$task_statuses rejected"
  task_statuses="$task_statuses partially_resolved"
  task_statuses="$task_statuses still_failing"
  task_statuses="$task_statuses inconclusive"
  task_statuses="$task_statuses regressed"
  task_statuses="$task_statuses superseded"
  local command_context=$command command_options=''
  if [[ -n "$operation" ]]; then command_context="$command:$operation"; fi
  case "$command_context" in
    projects)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    findings)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --indicator"
      command_options="$command_options --severity"
      command_options="$command_options --path"
      command_options="$command_options --limit"
      command_options="$command_options --cursor"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    plan)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --revision"
      command_options="$command_options --against-revision"
      command_options="$command_options --limit"
      command_options="$command_options --cursor"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --dry-run"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    audit)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --revision"
      command_options="$command_options --limit"
      command_options="$command_options --cursor"
      command_options="$command_options --signing-key"
      command_options="$command_options --verification-key"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    apply)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --task"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --dry-run"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    tasks)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --revision"
      command_options="$command_options --task"
      command_options="$command_options --status"
      command_options="$command_options --limit"
      command_options="$command_options --cursor"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    status)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --all"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    refresh)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    verify)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --revision"
      command_options="$command_options --task"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    recover)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    doctor)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --release"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    config)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    completion)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    manpage)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    help)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    version)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    plan:create)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --dry-run"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    plan:list)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --limit"
      command_options="$command_options --cursor"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --dry-run"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    plan:show)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --revision"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --dry-run"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    plan:approve)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --dry-run"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    plan:diff)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --revision"
      command_options="$command_options --against-revision"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --dry-run"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    plan:explain)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --revision"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --dry-run"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    plan:graph)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --run"
      command_options="$command_options --revision"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --dry-run"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    audit:export)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --revision"
      command_options="$command_options --limit"
      command_options="$command_options --cursor"
      command_options="$command_options --signing-key"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
    audit:verify)
      command_options="$command_options --config"
      command_options="$command_options --database"
      command_options="$command_options --state"
      command_options="$command_options --project"
      command_options="$command_options --format"
      command_options="$command_options --color"
      command_options="$command_options --progress"
      command_options="$command_options --revision"
      command_options="$command_options --limit"
      command_options="$command_options --cursor"
      command_options="$command_options --verification-key"
      command_options="$command_options --agent-model"
      command_options="$command_options --agent-model-path"
      command_options="$command_options --agent-model-sha256"
      command_options="$command_options --no-agent"
      command_options="$command_options --verbose"
      command_options="$command_options --quiet"
      command_options="$command_options --help"
      ;;
  esac
  local words='' value_context=${inline_option:-$prev}
  if [[ -z "$command" ]]; then words="$commands $options"; else words="$command_options"; fi
  if [[ -n "$command" && "$value_context" == --* && " $command_options " != *" $value_context "* ]]; then
    COMPREPLY=()
    return
  fi
  case "$value_context" in
    --config) compopt -o filenames 2>/dev/null || true
       COMPREPLY=(); while IFS= read -r word; do
         COMPREPLY+=("$inline_prefix$word")
       done < <(compgen -f -- "$cur"); return ;;
    --database) compopt -o filenames 2>/dev/null || true
       COMPREPLY=(); while IFS= read -r word; do
         COMPREPLY+=("$inline_prefix$word")
       done < <(compgen -f -- "$cur"); return ;;
    --state) compopt -o filenames 2>/dev/null || true
       COMPREPLY=(); while IFS= read -r word; do
         COMPREPLY+=("$inline_prefix$word")
       done < <(compgen -f -- "$cur"); return ;;
    --format) words='terminal json markdown dot' ;;
    --color) words='auto always never' ;;
    --progress) words='auto always never' ;;
    --severity) words='critical high medium low info' ;;
    --path) compopt -o filenames 2>/dev/null || true
       COMPREPLY=(); while IFS= read -r word; do
         COMPREPLY+=("$inline_prefix$word")
       done < <(compgen -f -- "$cur"); return ;;
    --signing-key) compopt -o filenames 2>/dev/null || true
       COMPREPLY=(); while IFS= read -r word; do
         COMPREPLY+=("$inline_prefix$word")
       done < <(compgen -f -- "$cur"); return ;;
    --verification-key) compopt -o filenames 2>/dev/null || true
       COMPREPLY=(); while IFS= read -r word; do
         COMPREPLY+=("$inline_prefix$word")
       done < <(compgen -f -- "$cur"); return ;;
    --agent-model-path) compopt -o filenames 2>/dev/null || true
       COMPREPLY=(); while IFS= read -r word; do
         COMPREPLY+=("$inline_prefix$word")
       done < <(compgen -f -- "$cur"); return ;;
    --status) words="$task_statuses" ;;
    *) case "$command" in
         plan) words="list show approve diff explain graph $command_options" ;;
         audit) words="verify $command_options" ;;
         config) words="show validate explain $command_options" ;;
         completion) words="bash zsh fish $command_options" ;;
         help) words="$commands $command_options" ;;
       esac ;;
  esac
  COMPREPLY=()
  while IFS= read -r word; do COMPREPLY+=("$inline_prefix$word"); done < <(compgen -W "$words" -- "$cur")
}
complete -F _improve_complete improve
