set -l improve_commands
set -a improve_commands projects
set -a improve_commands findings
set -a improve_commands plan
set -a improve_commands audit
set -a improve_commands apply
set -a improve_commands tasks
set -a improve_commands status
set -a improve_commands refresh
set -a improve_commands verify
set -a improve_commands recover
set -a improve_commands doctor
set -a improve_commands config
set -a improve_commands completion
set -a improve_commands manpage
set -a improve_commands help
set -a improve_commands version
set -l improve_statuses 'all unresolved'
set improve_statuses "$improve_statuses proposed"
set improve_statuses "$improve_statuses published"
set improve_statuses "$improve_statuses in_progress"
set improve_statuses "$improve_statuses awaiting_verification"
set improve_statuses "$improve_statuses verified"
set improve_statuses "$improve_statuses blocked"
set improve_statuses "$improve_statuses failed"
set improve_statuses "$improve_statuses cancelled"
set improve_statuses "$improve_statuses rejected"
set improve_statuses "$improve_statuses partially_resolved"
set improve_statuses "$improve_statuses still_failing"
set improve_statuses "$improve_statuses inconclusive"
set improve_statuses "$improve_statuses regressed"
set improve_statuses "$improve_statuses superseded"
function __improve_command_state --argument-names expected
    set -l skip_next 0
    for token in (commandline -opc)[2..-1]
        if test $skip_next -eq 1
            set skip_next 0
            continue
        end
        switch $token
            case '--*=*'
                continue
            case '--config'
                set skip_next 1
                continue
            case '--database'
                set skip_next 1
                continue
            case '--state'
                set skip_next 1
                continue
            case '--project'
                set skip_next 1
                continue
            case '--format'
                set skip_next 1
                continue
            case '--color'
                set skip_next 1
                continue
            case '--progress'
                set skip_next 1
                continue
            case '--run'
                set skip_next 1
                continue
            case '--revision'
                set skip_next 1
                continue
            case '--against-revision'
                set skip_next 1
                continue
            case '--task'
                set skip_next 1
                continue
            case '--status'
                set skip_next 1
                continue
            case '--indicator'
                set skip_next 1
                continue
            case '--severity'
                set skip_next 1
                continue
            case '--path'
                set skip_next 1
                continue
            case '--limit'
                set skip_next 1
                continue
            case '--cursor'
                set skip_next 1
                continue
            case '--signing-key'
                set skip_next 1
                continue
            case '--verification-key'
                set skip_next 1
                continue
            case '--agent-model'
                set skip_next 1
                continue
            case '--agent-model-path'
                set skip_next 1
                continue
            case '--agent-model-sha256'
                set skip_next 1
                continue
            case 'projects'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'findings'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'plan'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'audit'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'apply'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'tasks'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'status'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'refresh'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'verify'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'recover'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'doctor'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'config'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'completion'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'manpage'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'help'
                test -n "$expected"; and test "$token" = "$expected"
                return
            case 'version'
                test -n "$expected"; and test "$token" = "$expected"
                return
        end
    end
    test $skip_next -eq 0; and test -z "$expected"
end
function __improve_option_state
    set -l command ''
    set -l operation ''
    set -l skip_next 0
    for token in (commandline -opc)[2..-1]
        if test $skip_next -eq 1
            set skip_next 0
            continue
        end
        switch $token
            case '--*=*'
                continue
            case '--config'
                set skip_next 1
                continue
            case '--database'
                set skip_next 1
                continue
            case '--state'
                set skip_next 1
                continue
            case '--project'
                set skip_next 1
                continue
            case '--format'
                set skip_next 1
                continue
            case '--color'
                set skip_next 1
                continue
            case '--progress'
                set skip_next 1
                continue
            case '--run'
                set skip_next 1
                continue
            case '--revision'
                set skip_next 1
                continue
            case '--against-revision'
                set skip_next 1
                continue
            case '--task'
                set skip_next 1
                continue
            case '--status'
                set skip_next 1
                continue
            case '--indicator'
                set skip_next 1
                continue
            case '--severity'
                set skip_next 1
                continue
            case '--path'
                set skip_next 1
                continue
            case '--limit'
                set skip_next 1
                continue
            case '--cursor'
                set skip_next 1
                continue
            case '--signing-key'
                set skip_next 1
                continue
            case '--verification-key'
                set skip_next 1
                continue
            case '--agent-model'
                set skip_next 1
                continue
            case '--agent-model-path'
                set skip_next 1
                continue
            case '--agent-model-sha256'
                set skip_next 1
                continue
            case '--*'
                continue
        end
        if test -z "$command"
            switch $token
                case 'projects'
                    set command $token
                    continue
                case 'findings'
                    set command $token
                    continue
                case 'plan'
                    set command $token
                    continue
                case 'audit'
                    set command $token
                    continue
                case 'apply'
                    set command $token
                    continue
                case 'tasks'
                    set command $token
                    continue
                case 'status'
                    set command $token
                    continue
                case 'refresh'
                    set command $token
                    continue
                case 'verify'
                    set command $token
                    continue
                case 'recover'
                    set command $token
                    continue
                case 'doctor'
                    set command $token
                    continue
                case 'config'
                    set command $token
                    continue
                case 'completion'
                    set command $token
                    continue
                case 'manpage'
                    set command $token
                    continue
                case 'help'
                    set command $token
                    continue
                case 'version'
                    set command $token
                    continue
            end
        else if test -z "$operation"
            if test "$command" = plan
                switch $token
                    case 'list'
                        set operation $token
                    case 'show'
                        set operation $token
                    case 'approve'
                        set operation $token
                    case 'diff'
                        set operation $token
                    case 'explain'
                        set operation $token
                    case 'graph'
                        set operation $token
                end
            else if test "$command" = audit
                if test "$token" = verify
                    set operation verify
                else
                    set operation export
                end
            end
        end
    end
    test -z "$command"; and return 0
    set -l context $command
    test -n "$operation"; and set context $command:$operation
    set -l option $argv[1]
    switch $option:$context
        case 'run:findings'
            return 0
        case 'run:plan'
            return 0
        case 'run:verify'
            return 0
        case 'run:plan:create'
            return 0
        case 'run:plan:list'
            return 0
        case 'run:plan:show'
            return 0
        case 'run:plan:approve'
            return 0
        case 'run:plan:diff'
            return 0
        case 'run:plan:explain'
            return 0
        case 'run:plan:graph'
            return 0
        case 'revision:plan'
            return 0
        case 'revision:audit'
            return 0
        case 'revision:tasks'
            return 0
        case 'revision:verify'
            return 0
        case 'revision:plan:show'
            return 0
        case 'revision:plan:diff'
            return 0
        case 'revision:plan:explain'
            return 0
        case 'revision:plan:graph'
            return 0
        case 'revision:audit:export'
            return 0
        case 'revision:audit:verify'
            return 0
        case 'against-revision:plan'
            return 0
        case 'against-revision:plan:diff'
            return 0
        case 'task:apply'
            return 0
        case 'task:tasks'
            return 0
        case 'task:verify'
            return 0
        case 'status:tasks'
            return 0
        case 'indicator:findings'
            return 0
        case 'severity:findings'
            return 0
        case 'path:findings'
            return 0
        case 'limit:findings'
            return 0
        case 'limit:plan'
            return 0
        case 'limit:audit'
            return 0
        case 'limit:tasks'
            return 0
        case 'limit:plan:list'
            return 0
        case 'limit:audit:export'
            return 0
        case 'limit:audit:verify'
            return 0
        case 'cursor:findings'
            return 0
        case 'cursor:plan'
            return 0
        case 'cursor:audit'
            return 0
        case 'cursor:tasks'
            return 0
        case 'cursor:plan:list'
            return 0
        case 'cursor:audit:export'
            return 0
        case 'cursor:audit:verify'
            return 0
        case 'signing-key:audit'
            return 0
        case 'signing-key:audit:export'
            return 0
        case 'verification-key:audit'
            return 0
        case 'verification-key:audit:verify'
            return 0
        case 'dry-run:plan'
            return 0
        case 'dry-run:apply'
            return 0
        case 'dry-run:plan:create'
            return 0
        case 'dry-run:plan:list'
            return 0
        case 'dry-run:plan:show'
            return 0
        case 'dry-run:plan:approve'
            return 0
        case 'dry-run:plan:diff'
            return 0
        case 'dry-run:plan:explain'
            return 0
        case 'dry-run:plan:graph'
            return 0
        case 'release:doctor'
            return 0
        case 'all:status'
            return 0
    end
    return 1
end
complete -c improve -f -n '__improve_command_state' -a "$improve_commands"
complete -c improve -f -n '__improve_command_state plan' -a 'list show approve diff explain graph'
complete -c improve -f -n '__improve_command_state audit' -a 'verify'
complete -c improve -f -n '__improve_command_state config' -a 'show validate explain'
complete -c improve -f -n '__improve_command_state completion' -a 'bash zsh fish'
complete -c improve -f -n '__improve_command_state help' -a "$improve_commands"
complete -c improve -l config -r -F
complete -c improve -l database -r -F
complete -c improve -l state -r -F
complete -c improve -l project -r
complete -c improve -l format -r -a 'terminal json markdown dot'
complete -c improve -l color -r -a 'auto always never'
complete -c improve -l progress -r -a 'auto always never'
complete -c improve -l run -n '__improve_option_state run' -r
complete -c improve -l revision -n '__improve_option_state revision' -r
complete -c improve -l against-revision -n '__improve_option_state against-revision' -r
complete -c improve -l task -n '__improve_option_state task' -r
complete -c improve -l status -n '__improve_option_state status' -r -a "$improve_statuses"
complete -c improve -l indicator -n '__improve_option_state indicator' -r
complete -c improve -l severity -n '__improve_option_state severity' -r -a 'critical high medium low info'
complete -c improve -l path -n '__improve_option_state path' -r -F
complete -c improve -l limit -n '__improve_option_state limit' -r
complete -c improve -l cursor -n '__improve_option_state cursor' -r
complete -c improve -l signing-key -n '__improve_option_state signing-key' -r -F
complete -c improve -l verification-key -n '__improve_option_state verification-key' -r -F
complete -c improve -l agent-model -r
complete -c improve -l agent-model-path -r -F
complete -c improve -l agent-model-sha256 -r
complete -c improve -l no-agent
complete -c improve -l dry-run -n '__improve_option_state dry-run'
complete -c improve -l release -n '__improve_option_state release'
complete -c improve -l all -n '__improve_option_state all'
complete -c improve -l verbose
complete -c improve -l quiet
complete -c improve -l help
complete -c improve -l version -n '__improve_option_state version'
