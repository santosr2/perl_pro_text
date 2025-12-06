# Fish completion for sift (PerlText Pro)
# Install: copy to ~/.config/fish/completions/sift.fish

# Disable file completions by default
complete -c sift -f

# Commands
complete -c sift -n "__fish_use_subcommand" -a query -d "Execute a log query"
complete -c sift -n "__fish_use_subcommand" -a find -d "Find log entries matching a pattern"
complete -c sift -n "__fish_use_subcommand" -a extract -d "Extract fields from logs"
complete -c sift -n "__fish_use_subcommand" -a formats -d "List supported log formats"
complete -c sift -n "__fish_use_subcommand" -a sources -d "List available log sources"

# Global options
complete -c sift -s h -l help -d "Show help message"
complete -c sift -s V -l version -d "Show version"

# Output formats
set -l output_formats table json csv yaml pretty chart

# Log formats
set -l log_formats nginx json syslog

# Source types
set -l source_types file k8s aws gcp azure

# Time durations
set -l time_durations 1h 30m 2h 6h 12h 1d 2d 7d

# Query command options
complete -c sift -n "__fish_seen_subcommand_from query" -s s -l since -d "Time filter" -xa "$time_durations"
complete -c sift -n "__fish_seen_subcommand_from query" -s u -l until -d "End time filter" -xa "$time_durations"
complete -c sift -n "__fish_seen_subcommand_from query" -s f -l format -d "Force log format" -xa "$log_formats"
complete -c sift -n "__fish_seen_subcommand_from query" -s o -l output -d "Output format" -xa "$output_formats"
complete -c sift -n "__fish_seen_subcommand_from query" -s l -l limit -d "Max events" -xa "10 25 50 100 500 1000"
complete -c sift -n "__fish_seen_subcommand_from query" -s e -l eval -d "Perl transform"
complete -c sift -n "__fish_seen_subcommand_from query" -s v -l verbose -d "Verbose output"
complete -c sift -n "__fish_seen_subcommand_from query" -l source -d "Source type" -xa "$source_types"
complete -c sift -n "__fish_seen_subcommand_from query" -s n -l namespace -d "K8s namespace" -xa "(__fish_sift_k8s_namespaces)"
complete -c sift -n "__fish_seen_subcommand_from query" -s p -l pod -d "K8s pod name" -xa "(__fish_sift_k8s_pods)"
complete -c sift -n "__fish_seen_subcommand_from query" -l selector -d "K8s label selector"
complete -c sift -n "__fish_seen_subcommand_from query" -l log-group -d "AWS log group" -xa "(__fish_sift_aws_log_groups)"
complete -c sift -n "__fish_seen_subcommand_from query" -l project -d "GCP project" -xa "(__fish_sift_gcp_projects)"
complete -c sift -n "__fish_seen_subcommand_from query" -l resource-group -d "Azure resource group"
complete -c sift -n "__fish_seen_subcommand_from query" -l profile -d "AWS profile" -xa "(__fish_sift_aws_profiles)"
complete -c sift -n "__fish_seen_subcommand_from query" -l region -d "Cloud region" -xa "us-east-1 us-east-2 us-west-1 us-west-2 eu-west-1 eu-west-2 eu-central-1 ap-northeast-1 ap-southeast-1 ap-southeast-2"
complete -c sift -n "__fish_seen_subcommand_from query" -s h -l help -d "Show help"
complete -c sift -n "__fish_seen_subcommand_from query" -F  # Enable file completion for query

# Find command options
complete -c sift -n "__fish_seen_subcommand_from find" -s f -l format -d "Force log format" -xa "$log_formats"
complete -c sift -n "__fish_seen_subcommand_from find" -s o -l output -d "Output format" -xa "$output_formats"
complete -c sift -n "__fish_seen_subcommand_from find" -s l -l limit -d "Max events" -xa "10 25 50 100 500 1000"
complete -c sift -n "__fish_seen_subcommand_from find" -s h -l help -d "Show help"
complete -c sift -n "__fish_seen_subcommand_from find" -F  # Enable file completion for find

# Extract command options
complete -c sift -n "__fish_seen_subcommand_from extract" -s p -l pattern -d "Regex pattern"
complete -c sift -n "__fish_seen_subcommand_from extract" -l fields -d "Fields to extract"
complete -c sift -n "__fish_seen_subcommand_from extract" -s o -l output -d "Output format" -xa "$output_formats"
complete -c sift -n "__fish_seen_subcommand_from extract" -s h -l help -d "Show help"
complete -c sift -n "__fish_seen_subcommand_from extract" -F  # Enable file completion for extract

# Helper functions for dynamic completions

function __fish_sift_k8s_namespaces
    if command -q kubectl
        kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null
    end
end

function __fish_sift_k8s_pods
    if command -q kubectl
        kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null
    end
end

function __fish_sift_aws_log_groups
    if command -q aws
        aws logs describe-log-groups --query 'logGroups[].logGroupName' --output text 2>/dev/null | string split \t
    end
end

function __fish_sift_aws_profiles
    if test -f ~/.aws/credentials
        grep '^\[' ~/.aws/credentials | string replace -ra '\[|\]' ''
    end
end

function __fish_sift_gcp_projects
    if command -q gcloud
        gcloud projects list --format='value(projectId)' 2>/dev/null
    end
end
