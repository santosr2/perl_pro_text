package Sift::Parser::Kubernetes;
use v5.36;
use Moo;
use DateTime::Format::ISO8601;
use Sift::Event;
use JSON::MaybeXS qw(decode_json);
use namespace::autoclean;

with 'Sift::Parser::Base';

has '+source_name' => (
    default => 'kubernetes',
);

sub format_name ($self) { 'kubernetes' }

# Kubernetes log formats:
#
# 1. kubectl logs with --timestamps:
#    2025-12-04T10:15:30.123456789Z log message here
#
# 2. JSON structured logs (common in cloud-native apps):
#    {"ts":"2025-12-04T10:15:30Z","level":"info","msg":"Starting server","pod":"api-xyz"}
#
# 3. klog format (used by K8s components):
#    I1204 10:15:30.123456   12345 server.go:123] Starting server
#    E1204 10:15:30.123456   12345 server.go:456] Error occurred
#
# 4. Plain text with optional level prefix:
#    [INFO] 2025-12-04 10:15:30 Starting server
#    ERROR: Something went wrong

# Timestamp pattern for kubectl --timestamps output
my $K8S_TIMESTAMP = qr{(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?)};

# klog format: I1204 10:15:30.123456 PID file:line] message
my $KLOG_REGEX = qr{
    ^
    ([IWEF])                           # Log level
    (\d{4})                            # MMDD
    \s+
    (\d{2}:\d{2}:\d{2})                # HH:MM:SS
    (?:\.(\d+))?                       # Optional microseconds
    \s+
    (\d+)                              # PID
    \s+
    ([^:]+):(\d+)                      # file:line
    \]\s+
    (.*)                               # message
    $
}x;

# JSON log detection
my $JSON_START = qr/^\s*\{/;

# Level patterns
my %LEVEL_MAP = (
    I => 'info',
    W => 'warning',
    E => 'error',
    F => 'fatal',
);

my %TEXT_LEVELS = (
    DEBUG   => 'debug',
    INFO    => 'info',
    WARN    => 'warning',
    WARNING => 'warning',
    ERROR   => 'error',
    FATAL   => 'fatal',
    PANIC   => 'fatal',
);

sub can_parse ($self, $line) {
    return 0 unless defined $line && $line =~ /\S/;

    # kubectl timestamps format
    return 1 if $line =~ /^$K8S_TIMESTAMP\s+/;

    # klog format
    return 1 if $line =~ $KLOG_REGEX;

    # JSON with kubernetes-like fields
    if ($line =~ $JSON_START) {
        my $data = eval { decode_json($line) };
        return 1 if $data && (
            exists $data->{pod} ||
            exists $data->{namespace} ||
            exists $data->{container} ||
            exists $data->{kubernetes}
        );
    }

    return 0;
}

sub parse ($self, $line, $source = undef) {
    return undef unless defined $line && $line =~ /\S/;

    # Try JSON first
    if ($line =~ $JSON_START) {
        my $event = $self->_parse_json($line, $source);
        return $event if $event;
    }

    # Try klog format
    if ($line =~ $KLOG_REGEX) {
        return $self->_parse_klog($line, $source);
    }

    # Try kubectl --timestamps format
    if ($line =~ /^$K8S_TIMESTAMP\s+(.*)$/) {
        return $self->_parse_kubectl_timestamps($1, $2, $source);
    }

    # Try plain text with level prefix
    return $self->_parse_text($line, $source);
}

sub _parse_json ($self, $line, $source) {
    my $data = eval { decode_json($line) };
    return undef if $@ || !$data;

    # Check for kubernetes-related fields
    my $is_k8s = exists $data->{pod} ||
                 exists $data->{namespace} ||
                 exists $data->{container} ||
                 exists $data->{kubernetes};

    return undef unless $is_k8s || exists $data->{level} || exists $data->{msg};

    my %fields;

    # Extract common fields
    $fields{level}   = lc($data->{level} // $data->{severity} // 'info');
    $fields{message} = $data->{msg} // $data->{message} // $data->{log} // '';

    # Kubernetes metadata
    $fields{namespace} = $data->{namespace} if $data->{namespace};
    $fields{pod}       = $data->{pod}       if $data->{pod};
    $fields{container} = $data->{container} if $data->{container};

    # Handle nested kubernetes metadata
    if (my $k8s = $data->{kubernetes}) {
        $fields{namespace} //= $k8s->{namespace_name};
        $fields{pod}       //= $k8s->{pod_name};
        $fields{container} //= $k8s->{container_name};
    }

    # Copy other fields
    for my $key (keys %$data) {
        next if $key =~ /^(level|severity|msg|message|log|ts|timestamp|time|kubernetes)$/;
        $fields{$key} = $data->{$key};
    }

    # Parse timestamp
    my $timestamp = time();
    my $ts_str = $data->{ts} // $data->{timestamp} // $data->{time};
    if ($ts_str) {
        my $dt = eval { DateTime::Format::ISO8601->parse_datetime($ts_str) };
        $timestamp = $dt->epoch if $dt;
    }

    return Sift::Event->new(
        timestamp => $timestamp,
        source    => $source // $self->source_name,
        raw       => $line,
        fields    => \%fields,
    );
}

sub _parse_klog ($self, $line, $source) {
    return undef unless $line =~ $KLOG_REGEX;

    my ($level_char, $mmdd, $time, $usec, $pid, $file, $line_num, $message) =
        ($1, $2, $3, $4, $5, $6, $7, $8);

    my $level = $LEVEL_MAP{$level_char} // 'info';

    # Build timestamp (assume current year)
    my $year = (localtime)[5] + 1900;
    my $month = substr($mmdd, 0, 2);
    my $day   = substr($mmdd, 2, 2);

    my $timestamp = time();
    if ($time =~ /(\d{2}):(\d{2}):(\d{2})/) {
        my $dt = eval {
            DateTime->new(
                year   => $year,
                month  => int($month),
                day    => int($day),
                hour   => int($1),
                minute => int($2),
                second => int($3),
            );
        };
        $timestamp = $dt->epoch if $dt;
    }

    return Sift::Event->new(
        timestamp => $timestamp,
        source    => $source // $self->source_name,
        raw       => $line,
        fields    => {
            level    => $level,
            message  => $message,
            pid      => int($pid),
            file     => $file,
            line     => int($line_num),
        },
    );
}

sub _parse_kubectl_timestamps ($self, $timestamp_str, $message, $source) {
    my $timestamp = time();
    if ($timestamp_str) {
        my $dt = eval { DateTime::Format::ISO8601->parse_datetime($timestamp_str) };
        $timestamp = $dt->epoch if $dt;
    }

    # Try to detect log level from message
    my $level = 'info';
    my $clean_message = $message;

    if ($message =~ /^\[?(DEBUG|INFO|WARN(?:ING)?|ERROR|FATAL|PANIC)\]?:?\s*/i) {
        $level = $TEXT_LEVELS{uc $1} // 'info';
        $clean_message = $';
    }
    elsif ($message =~ /^(debug|info|warn(?:ing)?|error|fatal|panic):\s*/i) {
        $level = $TEXT_LEVELS{uc $1} // 'info';
        $clean_message = $';
    }

    return Sift::Event->new(
        timestamp => $timestamp,
        source    => $source // $self->source_name,
        raw       => "$timestamp_str $message",
        fields    => {
            level   => $level,
            message => $clean_message,
        },
    );
}

sub _parse_text ($self, $line, $source) {
    my $level = 'info';
    my $message = $line;
    my $timestamp = time();

    # Try to extract level
    if ($line =~ /^\[?(DEBUG|INFO|WARN(?:ING)?|ERROR|FATAL|PANIC)\]?:?\s*/i) {
        $level = $TEXT_LEVELS{uc $1} // 'info';
        $message = $';
    }

    # Try to extract timestamp from message
    if ($message =~ /^(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)\s+(.*)$/i) {
        my $ts_str = $1;
        $message = $2;
        my $dt = eval { DateTime::Format::ISO8601->parse_datetime($ts_str) };
        $timestamp = $dt->epoch if $dt;
    }

    return Sift::Event->new(
        timestamp => $timestamp,
        source    => $source // $self->source_name,
        raw       => $line,
        fields    => {
            level   => $level,
            message => $message,
        },
    );
}

1;

__END__

=head1 NAME

Sift::Parser::Kubernetes - Parser for Kubernetes pod logs

=head1 SYNOPSIS

    use Sift::Parser::Kubernetes;

    my $parser = Sift::Parser::Kubernetes->new;
    my $event = $parser->parse_line($log_line);

=head1 DESCRIPTION

Parses various Kubernetes log formats including:

=over 4

=item * kubectl logs --timestamps output

=item * JSON structured logs with kubernetes metadata

=item * klog format (used by Kubernetes components)

=item * Plain text with level prefixes

=back

=head2 Extracted Fields

=over 4

=item * level - Log level (debug, info, warning, error, fatal)

=item * message - Log message

=item * namespace - Kubernetes namespace

=item * pod - Pod name

=item * container - Container name

=item * pid - Process ID (klog format)

=item * file - Source file (klog format)

=item * line - Line number (klog format)

=back

=head1 SUPPORTED FORMATS

=head2 kubectl --timestamps

    2025-12-04T10:15:30.123456789Z Starting server on port 8080

=head2 JSON Structured

    {"ts":"2025-12-04T10:15:30Z","level":"info","msg":"Ready","pod":"api-xyz"}

=head2 klog Format

    I1204 10:15:30.123456   12345 server.go:123] Starting server

=head2 Plain Text

    [INFO] Starting server
    ERROR: Connection failed

=cut
