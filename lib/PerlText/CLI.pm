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
    local @ARGV = @argv;

    my ($opt, $usage) = describe_options(
        'ptx %o <command> [args...]',
        [ 'help|h',    'Show this help message' ],
        [ 'version|V', 'Show version' ],
        [],
        [ 'Commands:' ],
        [ '  query      Execute a log query' ],
        [ '  extract    Extract fields with patterns' ],
        [ '  find       Find matching log entries' ],
        [ '  formats    List supported log formats' ],
        [ '  sources    List available sources' ],
    );

    if ($opt->help || !@ARGV) {
        print $usage->text;
        return 0;
    }

    if ($opt->version) {
        say "ptx version $VERSION";
        return 0;
    }

    my $command = shift @ARGV;

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
        print $usage->text;
        return 1;
    }

    return $handler->($self, @ARGV);
}

sub cmd_query ($self, @args) {
    local @ARGV = @args;

    my ($opt, $usage) = describe_options(
        'ptx query %o <query> [files...]',
        [ 'since|s=s',  'Time filter (e.g., 1h, 30m, 2d)' ],
        [ 'until|u=s',  'End time filter' ],
        [ 'format|f=s', 'Force log format (nginx, json, syslog)' ],
        [ 'output|o=s', 'Output format (table, json, csv)', { default => 'table' } ],
        [ 'limit|l=i',  'Max events to return' ],
        [ 'eval|e=s',   'Perl transformation expression' ],
        [ 'verbose|v',  'Verbose output' ],
        [ 'help|h',     'Show help' ],
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

    my @files = @ARGV;
    unless (@files) {
        # Read from STDIN
        push @files, '-';
    }

    # Parse query
    my ($ast, $error) = $self->query_parser->try_parse($query_string);
    if ($error) {
        say STDERR colored(['red'], "Parse error: $error");
        return 1;
    }

    # Read and parse events
    my @events;
    for my $file (@files) {
        push @events, $self->_read_events($file, $opt)->@*;
    }

    # Execute query
    my $executor = PerlText::Query::Executor->new(events => \@events);
    my $results  = $executor->execute($ast);

    # Output results
    $self->_output_results($results, $opt->output);

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

    say STDERR "Detected format: " . $parser->format_name if $opt->verbose;

    return $parser->parse_lines(\@lines, $file);
}

sub _output_results ($self, $results, $format) {
    my $formatter = $self->_get_formatter($format);
    print $formatter->format($results);
}

sub _get_formatter ($self, $format) {
    my %formatters = (
        table => 'PerlText::Output::Table',
        json  => 'PerlText::Output::JSON',
        csv   => 'PerlText::Output::CSV',
    );

    my $class = $formatters{$format} // $formatters{table};
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
