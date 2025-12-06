# Bash completion for sift (PerlText Pro)
# Install: source this file or add to ~/.bashrc

_sift_completions() {
    local cur prev words cword
    _init_completion || return

    local commands="query find extract formats sources"
    local output_formats="table json csv yaml pretty chart"
    local log_formats="nginx json syslog"
    local source_types="file k8s aws gcp azure"

    # Global options
    local global_opts="-h --help -V --version"

    # Command-specific options
    local query_opts="-s --since -u --until -f --format -o --output -l --limit -e --eval -v --verbose --source -n --namespace -p --pod --selector --log-group --project --resource-group --profile --region"
    local find_opts="-f --format -o --output -l --limit -h --help"
    local extract_opts="-p --pattern --fields -o --output -h --help"

    # Determine which command we're completing for
    local cmd=""
    local i
    for ((i=1; i < ${#words[@]} - 1; i++)); do
        case "${words[i]}" in
            query|find|extract|formats|sources)
                cmd="${words[i]}"
                break
                ;;
        esac
    done

    case "$prev" in
        -o|--output)
            COMPREPLY=($(compgen -W "$output_formats" -- "$cur"))
            return
            ;;
        -f|--format)
            COMPREPLY=($(compgen -W "$log_formats" -- "$cur"))
            return
            ;;
        --source)
            COMPREPLY=($(compgen -W "$source_types" -- "$cur"))
            return
            ;;
        -s|--since|-u|--until)
            # Suggest common time formats
            COMPREPLY=($(compgen -W "1h 30m 2h 6h 12h 1d 2d 7d" -- "$cur"))
            return
            ;;
        -n|--namespace)
            # Try to get kubernetes namespaces
            if command -v kubectl &>/dev/null; then
                local namespaces
                namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
                COMPREPLY=($(compgen -W "$namespaces" -- "$cur"))
            fi
            return
            ;;
        -l|--limit)
            COMPREPLY=($(compgen -W "10 25 50 100 500 1000" -- "$cur"))
            return
            ;;
        --log-group)
            # Try to get AWS log groups
            if command -v aws &>/dev/null; then
                local groups
                groups=$(aws logs describe-log-groups --query 'logGroups[].logGroupName' --output text 2>/dev/null | tr '\t' ' ')
                COMPREPLY=($(compgen -W "$groups" -- "$cur"))
            fi
            return
            ;;
        --profile)
            # AWS profiles from credentials file
            if [[ -f ~/.aws/credentials ]]; then
                local profiles
                profiles=$(grep '^\[' ~/.aws/credentials | tr -d '[]')
                COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
            fi
            return
            ;;
        --region)
            COMPREPLY=($(compgen -W "us-east-1 us-east-2 us-west-1 us-west-2 eu-west-1 eu-west-2 eu-central-1 ap-northeast-1 ap-southeast-1 ap-southeast-2" -- "$cur"))
            return
            ;;
        --project)
            # Try to get GCP projects
            if command -v gcloud &>/dev/null; then
                local projects
                projects=$(gcloud projects list --format='value(projectId)' 2>/dev/null)
                COMPREPLY=($(compgen -W "$projects" -- "$cur"))
            fi
            return
            ;;
    esac

    # If we haven't determined the command yet, complete commands or global options
    if [[ -z "$cmd" ]]; then
        if [[ "$cur" == -* ]]; then
            COMPREPLY=($(compgen -W "$global_opts" -- "$cur"))
        else
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        fi
        return
    fi

    # Complete command-specific options
    if [[ "$cur" == -* ]]; then
        case "$cmd" in
            query)
                COMPREPLY=($(compgen -W "$query_opts" -- "$cur"))
                ;;
            find)
                COMPREPLY=($(compgen -W "$find_opts" -- "$cur"))
                ;;
            extract)
                COMPREPLY=($(compgen -W "$extract_opts" -- "$cur"))
                ;;
        esac
        return
    fi

    # Default to file completion
    _filedir
}

complete -F _sift_completions sift
