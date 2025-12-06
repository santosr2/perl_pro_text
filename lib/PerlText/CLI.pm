package PerlText::CLI;
use v5.36;
use open qw(:std :utf8);
use Moo;
use Getopt::Long::Descriptive;
use Path::Tiny;
use Term::ANSIColor qw(colored);
use PerlText::Pro;
use PerlText::Parser::Detector;
use PerlText::Query::Parser;
use PerlText::Query::Executor;
use PerlText::Output::Table;
use PerlText::Output::JSON;
use PerlText::Output::CSV;
use PerlText::Output::YAML;
use PerlText::Output::Pretty;
use PerlText::Output::Chart;
use PerlText::Transform::Engine;
use PerlText::Transform::Eval;
use PerlText::Source::File;
use PerlText::Source::Stdin;
use PerlText::Source::Kubernetes;
use PerlText::Source::AWS::CloudWatch;
use PerlText::Source::GCP::Logging;
use PerlText::Source::Azure::Monitor;
use namespace::autoclean;

our $VERSION = '0.01';

has app => (
    is      => 'lazy',
    default => sub { PerlText::Pro->new },
);

has detector => (
    is      => 'lazy',
    default => sub { PerlText::Parser::Detector->new },
);

has query_parser => (
    is      => 'lazy',
    default => sub { PerlText::Query::Parser->new },
);

sub run ($self, @argv) {
    # Check for top-level flags before command
    if (!@argv || $argv[0] eq '--help' || $argv[0] eq '-h') {
        $self->_print_main_help;
        return 0;
    }

    if ($argv[0] eq '--version' || $argv[0] eq '-V') {
        say "ptx version $VERSION";
        return 0;
    }

    my $command = shift @argv;

    my %commands = (
        query   => \&cmd_query,
        extract => \&cmd_extract,
        find    => \&cmd_find,
        formats => \&cmd_formats,
        sources => \&cmd_sources,
    );

    my $handler = $commands{$command};
    unless ($handler) {
        say STDERR "Unknown command: $command";
        $self->_print_main_help;
        return 1;
    }

    return $handler->($self, @argv);
}

sub _print_main_help ($self) {
    say "ptx [-hV] <command> [args...]";
    say "    --help (or -h)     Show this help message";
    say "    --version (or -V)  Show version";
    say "";
    say "    Commands:";
    say "      query      Execute a log query";
    say "      extract    Extract fields with patterns";
    say "      find       Find matching log entries";
    say "      formats    List supported log formats";
    say "      sources    List available sources";
}

sub cmd_query ($self, @args) {
    local @ARGV = @args;

    my ($opt, $usage) = describe_options(
        'ptx query %o <query> [files...]',
        [ 'since|s=s',  'Time filter (e.g., 1h, 30m, 2d)' ],
        [ 'until|u=s',  'End time filter' ],
        [ 'format|f=s', 'Force log format (nginx, json, syslog)' ],
        [ 'output|o=s', 'Output format (table, json, csv, yaml, pretty, chart)', { default => 'table' } ],
        [ 'limit|l=i',  'Max events to return' ],
        [ 'eval|e=s',   'Perl transformation expression' ],
        [ 'verbose|v',  'Verbose output' ],
        [ 'help|h',     'Show help' ],
        [],
        [ 'Cloud sources:' ],
        [ 'source=s',      'Source type (file, k8s, aws, gcp, azure)' ],
        [ 'namespace|n=s', 'Kubernetes namespace' ],
        [ 'pod|p=s',       'Kubernetes pod name' ],
        [ 'selector=s',    'Kubernetes label selector' ],
        [ 'log-group=s',   'AWS CloudWatch log group' ],
        [ 'project=s',     'GCP project ID' ],
        [ 'resource-group=s', 'Azure resource group' ],
        [ 'profile=s',     'AWS profile name' ],
        [ 'region=s',      'AWS/Azure region' ],
    );

    if ($opt->help) {
        print $usage->text;
        return 0;
    }

    my $query_string = shift @ARGV;
    unless ($query_string) {
        say STDERR "Error: Query string required";
        print $usage->text;
        return 1;
    }

    # Parse query
    my ($ast, $error) = $self->query_parser->try_parse($query_string);
    if ($error) {
        say STDERR colored(['red'], "Parse error: $error");
        return 1;
    }

    # Read events from appropriate source
    my @events;
    if ($opt->source && $opt->source ne 'file') {
        @events = $self->_read_from_cloud($opt)->@*;
    }
    else {
        my @files = @ARGV;
        push @files, '-' unless @files;
        for my $file (@files) {
            push @events, $self->_read_events($file, $opt)->@*;
        }
    }

    # Apply --eval transformation if specified
    if ($opt->eval) {
        my $transform = PerlText::Transform::Eval->new(code => $opt->eval);
        my $engine = PerlText::Transform::Engine->new(transforms => [$transform]);
        @events = $engine->apply(\@events)->@*;
    }

    # Execute query
    my $executor = PerlText::Query::Executor->new(events => \@events);
    my $results  = $executor->execute($ast);

    # Output results
    $self->_output_results($results, $opt->output, $opt);

    return 0;
}

sub cmd_find ($self, @args) {
    local @ARGV = @args;

    my ($opt, $usage) = describe_options(
        'ptx find %o <pattern> [files...]',
        [ 'format|f=s', 'Force log format' ],
        [ 'output|o=s', 'Output format', { default => 'table' } ],
        [ 'limit|l=i',  'Max events' ],
        [ 'help|h',     'Show help' ],
    );

    if ($opt->help) {
        print $usage->text;
        return 0;
    }

    my $pattern = shift @ARGV;
    unless ($pattern) {
        say STDERR "Error: Pattern required";
        return 1;
    }

    my @files = @ARGV;
    push @files, '-' unless @files;

    my @events;
    for my $file (@files) {
        push @events, $self->_read_events($file, $opt)->@*;
    }

    # Filter by pattern (searches raw line and all fields)
    my $re = qr/$pattern/i;
    @events = grep {
        my $e = $_;
        ($e->raw // '') =~ $re ||
        grep { ($e->get($_) // '') =~ $re } $e->field_names
    } @events;

    @events = @events[0 .. $opt->limit - 1] if $opt->limit && @events > $opt->limit;

    $self->_output_results(\@events, $opt->output);
    return 0;
}

sub cmd_extract ($self, @args) {
    local @ARGV = @args;

    my ($opt, $usage) = describe_options(
        'ptx extract %o [files...]',
        [ 'pattern|p=s', 'Custom regex pattern with named captures' ],
        [ 'fields=s',    'Comma-separated list of fields to extract' ],
        [ 'output|o=s',  'Output format', { default => 'table' } ],
        [ 'help|h',      'Show help' ],
    );

    if ($opt->help) {
        print $usage->text;
        return 0;
    }

    my @files = @ARGV;
    push @files, '-' unless @files;

    my @events;
    for my $file (@files) {
        push @events, $self->_read_events($file, $opt)->@*;
    }

    # Filter fields if specified
    if ($opt->fields) {
        my @want_fields = split /,/, $opt->fields;
        @events = map {
            my $e = $_;
            my %filtered = map { $_ => $e->get($_) } @want_fields;
            PerlText::Event->new(
                timestamp => $e->timestamp,
                source    => $e->source,
                fields    => \%filtered,
            );
        } @events;
    }

    $self->_output_results(\@events, $opt->output);
    return 0;
}

sub cmd_formats ($self, @args) {
    say "Supported log formats:";
    say "";
    for my $format ($self->detector->available_formats->@*) {
        say "  - $format";
    }
    return 0;
}

sub cmd_sources ($self, @args) {
    say "Available log sources:";
    say "";
    say "  Local:";
    say "    - file     Local log files";
    say "    - stdin    Standard input";
    say "";
    say "  Cloud:";
    say "    - k8s      Kubernetes (kubectl logs)";
    say "    - aws      AWS CloudWatch Logs";
    say "    - gcp      GCP Cloud Logging";
    say "    - azure    Azure Monitor";
    return 0;
}

sub _read_events ($self, $file, $opt) {
    my @lines;

    if ($file eq '-') {
        @lines = <STDIN>;
    }
    else {
        my $path = path($file);
        unless ($path->exists) {
            say STDERR colored(['red'], "File not found: $file");
            return [];
        }
        @lines = $path->lines({ chomp => 1 });
    }

    my $parser;
    if ($opt->format) {
        # Use specified format
        my %parsers = (
            nginx  => 'PerlText::Parser::Nginx',
            apache => 'PerlText::Parser::Apache',
            json   => 'PerlText::Parser::JSON',
            syslog => 'PerlText::Parser::Syslog',
        );
        my $class = $parsers{$opt->format};
        unless ($class) {
            say STDERR colored(['yellow'], "Unknown format: " . $opt->format . ", auto-detecting");
            $parser = $self->detector->detect(\@lines);
        }
        else {
            require Module::Runtime;
            Module::Runtime::use_module($class);
            $parser = $class->new(source_name => $file);
        }
    }
    else {
        $parser = $self->detector->detect(\@lines);
    }

    unless ($parser) {
        say STDERR colored(['yellow'], "Could not detect log format for: $file");
        return [];
    }

    say STDERR "Detected format: " . $parser->format_name if $opt->can('verbose') && $opt->verbose;

    return $parser->parse_lines(\@lines, $file);
}

sub _read_from_cloud ($self, $opt) {
    my $source_type = $opt->source;

    if ($source_type eq 'k8s') {
        my $namespace = $opt->namespace or die "Kubernetes --namespace is required\n";
        my $source = PerlText::Source::Kubernetes->new(
            namespace => $namespace,
            ($opt->pod      ? (pod      => $opt->pod)      : ()),
            ($opt->selector ? (selector => $opt->selector) : ()),
            ($opt->since    ? (since    => $opt->since)    : ()),
        );
        return $source->fetch_events;
    }
    elsif ($source_type eq 'aws') {
        my $log_group = $opt->log_group or die "AWS --log-group is required\n";
        my $source = PerlText::Source::AWS::CloudWatch->new(
            log_group => $log_group,
            ($opt->profile ? (profile => $opt->profile) : ()),
            ($opt->region  ? (region  => $opt->region)  : ()),
            ($opt->limit   ? (limit   => $opt->limit)   : ()),
        );
        return $source->fetch_events(
            ($opt->since ? (start_time => $self->_parse_since($opt->since) * 1000) : ()),
        );
    }
    elsif ($source_type eq 'gcp') {
        my $project = $opt->project or die "GCP --project is required\n";
        my $source = PerlText::Source::GCP::Logging->new(
            project   => $project,
            ($opt->since ? (freshness => $opt->since) : ()),
            ($opt->limit ? (limit     => $opt->limit) : ()),
        );
        return $source->fetch_events;
    }
    elsif ($source_type eq 'azure') {
        my $source = PerlText::Source::Azure::Monitor->new(
            ($opt->resource_group ? (resource_group => $opt->resource_group) : ()),
            ($opt->limit          ? (max_events     => $opt->limit)          : ()),
        );
        return $source->fetch_events;
    }
    else {
        die "Unknown source type: $source_type\n";
    }
}

sub _parse_since ($self, $since) {
    # Parse time duration like "1h", "30m", "2d" into epoch timestamp
    my $now = time();

    if ($since =~ /^(\d+)h$/i) {
        return $now - ($1 * 3600);
    }
    elsif ($since =~ /^(\d+)m$/i) {
        return $now - ($1 * 60);
    }
    elsif ($since =~ /^(\d+)d$/i) {
        return $now - ($1 * 86400);
    }
    elsif ($since =~ /^(\d+)s$/i) {
        return $now - $1;
    }
    elsif ($since =~ /^\d+$/) {
        return $now - $since;  # Assume seconds
    }

    return $now - 3600;  # Default to 1 hour
}

sub _output_results ($self, $results, $format, $opt = undef) {
    my $formatter = $self->_get_formatter($format, $opt);
    print $formatter->format($results);
}

sub _get_formatter ($self, $format, $opt = undef) {
    my %formatters = (
        table  => 'PerlText::Output::Table',
        json   => 'PerlText::Output::JSON',
        csv    => 'PerlText::Output::CSV',
        yaml   => 'PerlText::Output::YAML',
        pretty => 'PerlText::Output::Pretty',
        chart  => 'PerlText::Output::Chart',
    );

    my $class = $formatters{$format} // $formatters{table};

    # Chart formatter may need additional config
    if ($format eq 'chart') {
        return $class->new(
            value_field => 'count',
        );
    }

    return $class->new;
}

1;

__END__

=head1 NAME

PerlText::CLI - Command-line interface for PerlText Pro

=head1 SYNOPSIS

    use PerlText::CLI;

    my $cli = PerlText::CLI->new;
    exit $cli->run(@ARGV);

=head1 COMMANDS

=head2 query

    ptx query 'status >= 500' access.log
    ptx query 'from nginx where method == "POST"' --output json

=head2 find

    ptx find 'error' /var/log/syslog

=head2 extract

    ptx extract --fields ip,status,path access.log

=head2 formats

    ptx formats

=head2 sources

    ptx sources

=cut
