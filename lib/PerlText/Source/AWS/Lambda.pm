package PerlText::Source::AWS::Lambda;
use v5.36;
use Moo;
use Types::Standard qw(Str Int Maybe ArrayRef);
use IPC::Run3;
use JSON::MaybeXS qw(decode_json);
use PerlText::Event;
use namespace::autoclean;

has function_name => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has profile => (
    is      => 'ro',
    isa     => Maybe[Str],
    default => undef,
);

has region => (
    is      => 'ro',
    isa     => Maybe[Str],
    default => undef,
);

has limit => (
    is      => 'ro',
    isa     => Int,
    default => 100,
);

has filter_pattern => (
    is      => 'ro',
    isa     => Maybe[Str],
    default => undef,
);

# Build the log group name for Lambda
sub _log_group ($self) {
    return '/aws/lambda/' . $self->function_name;
}

sub fetch_events ($self, %opts) {
    my $start_time = $opts{start_time};
    my $end_time   = $opts{end_time} // (time() * 1000);

    # Default to last hour if no start time
    $start_time //= (time() - 3600) * 1000;

    my @cmd = (
        'aws', 'logs', 'filter-log-events',
        '--log-group-name', $self->_log_group,
        '--start-time', $start_time,
        '--end-time', $end_time,
        '--limit', $self->limit,
        '--output', 'json',
    );

    push @cmd, '--profile', $self->profile if $self->profile;
    push @cmd, '--region', $self->region   if $self->region;
    push @cmd, '--filter-pattern', $self->filter_pattern if $self->filter_pattern;

    my ($stdout, $stderr);
    run3 \@cmd, undef, \$stdout, \$stderr;

    if ($?) {
        warn "AWS CLI error: $stderr\n" if $stderr;
        return [];
    }

    my $data = eval { decode_json($stdout) };
    if ($@ || !$data) {
        warn "JSON parse error: $@\n" if $@;
        return [];
    }

    my @events;
    for my $log_event ($data->{events}->@*) {
        push @events, $self->_parse_lambda_event($log_event);
    }

    return \@events;
}

sub _parse_lambda_event ($self, $log_event) {
    my $message   = $log_event->{message} // '';
    my $timestamp = ($log_event->{timestamp} // 0) / 1000;  # ms to seconds
    my $log_stream = $log_event->{logStreamName} // '';

    my %fields = (
        message     => $message,
        log_stream  => $log_stream,
        log_group   => $self->_log_group,
        function    => $self->function_name,
    );

    # Parse Lambda-specific log formats

    # START RequestId: uuid Version: $LATEST
    if ($message =~ /^START RequestId: ([\w-]+)\s+Version: (.+)/) {
        $fields{type}       = 'start';
        $fields{request_id} = $1;
        $fields{version}    = $2;
        $fields{level}      = 'info';
    }
    # END RequestId: uuid
    elsif ($message =~ /^END RequestId: ([\w-]+)/) {
        $fields{type}       = 'end';
        $fields{request_id} = $1;
        $fields{level}      = 'info';
    }
    # REPORT RequestId: uuid Duration: 100.00 ms Billed Duration: 100 ms Memory Size: 128 MB Max Memory Used: 64 MB
    elsif ($message =~ /^REPORT RequestId: ([\w-]+)\s+Duration: ([\d.]+) ms\s+Billed Duration: (\d+) ms\s+Memory Size: (\d+) MB\s+Max Memory Used: (\d+) MB/) {
        $fields{type}            = 'report';
        $fields{request_id}      = $1;
        $fields{duration}        = 0 + $2;
        $fields{billed_duration} = int($3);
        $fields{memory_size}     = int($4);
        $fields{max_memory_used} = int($5);
        $fields{level}           = 'info';

        # Check for Init Duration (cold start)
        if ($message =~ /Init Duration: ([\d.]+) ms/) {
            $fields{init_duration} = 0 + $1;
            $fields{cold_start}    = 1;
        } else {
            $fields{cold_start} = 0;
        }

        # Check for XRAY trace
        if ($message =~ /XRAY TraceId: ([\w-]+)/) {
            $fields{xray_trace_id} = $1;
        }
    }
    # Error/timeout messages
    elsif ($message =~ /^(Task timed out|RequestId: [\w-]+ Error|Process exited before completing)/) {
        $fields{type}  = 'error';
        $fields{level} = 'error';

        if ($message =~ /RequestId: ([\w-]+)/) {
            $fields{request_id} = $1;
        }
    }
    # JSON structured logs
    elsif ($message =~ /^\s*\{/) {
        my $json = eval { decode_json($message) };
        if ($json && ref $json eq 'HASH') {
            $fields{type}  = 'structured';
            $fields{level} = lc($json->{level} // $json->{severity} // 'info');

            # Copy all JSON fields
            for my $key (keys %$json) {
                $fields{$key} = $json->{$key} unless exists $fields{$key};
            }
        }
    }
    # Regular log line with timestamp prefix
    elsif ($message =~ /^(\d{4}-\d{2}-\d{2}T[\d:.]+Z)\s+([\w-]+)\s+(.*)/) {
        $fields{log_timestamp} = $1;
        $fields{request_id}    = $2;
        $fields{message}       = $3;
        $fields{type}          = 'log';

        # Detect log level from message
        if ($fields{message} =~ /^\[?(ERROR|WARN(?:ING)?|INFO|DEBUG)\]?:?\s*/i) {
            $fields{level} = lc($1);
            $fields{message} = $';
        } else {
            $fields{level} = 'info';
        }
    }
    else {
        $fields{type}  = 'log';
        $fields{level} = 'info';
    }

    # Extract request ID from log stream name if not already set
    # Format: YYYY/MM/DD/[$LATEST or version]/random
    if (!$fields{request_id} && $log_stream =~ m{/\[([^\]]+)\]/}) {
        $fields{lambda_version} = $1;
    }

    return PerlText::Event->new(
        timestamp => $timestamp,
        source    => 'aws:lambda:' . $self->function_name,
        raw       => $message,
        fields    => \%fields,
    );
}

# Get invocation statistics from logs
sub get_stats ($self, %opts) {
    my $events = $self->fetch_events(%opts);

    my @reports = grep { ($_->get('type') // '') eq 'report' } @$events;

    return {} unless @reports;

    my @durations    = map { $_->get('duration') // 0 } @reports;
    my @memory_used  = map { $_->get('max_memory_used') // 0 } @reports;
    my $cold_starts  = grep { $_->get('cold_start') } @reports;

    use List::Util qw(sum min max);

    return {
        invocation_count => scalar(@reports),
        cold_start_count => $cold_starts,
        duration => {
            avg => sum(@durations) / @durations,
            min => min(@durations),
            max => max(@durations),
        },
        memory => {
            avg => sum(@memory_used) / @memory_used,
            min => min(@memory_used),
            max => max(@memory_used),
        },
    };
}

# List recent Lambda invocations
sub list_invocations ($self, %opts) {
    my $events = $self->fetch_events(%opts);

    my %invocations;
    for my $event (@$events) {
        my $request_id = $event->get('request_id');
        next unless $request_id;

        $invocations{$request_id} //= {
            request_id => $request_id,
            events     => [],
        };

        push $invocations{$request_id}{events}->@*, $event;

        my $type = $event->get('type') // '';
        if ($type eq 'start') {
            $invocations{$request_id}{start_time} = $event->timestamp;
        }
        elsif ($type eq 'report') {
            $invocations{$request_id}{duration}        = $event->get('duration');
            $invocations{$request_id}{billed_duration} = $event->get('billed_duration');
            $invocations{$request_id}{memory_used}     = $event->get('max_memory_used');
            $invocations{$request_id}{cold_start}      = $event->get('cold_start');
        }
        elsif ($type eq 'error') {
            $invocations{$request_id}{has_error} = 1;
        }
    }

    return [ values %invocations ];
}

1;

__END__

=head1 NAME

PerlText::Source::AWS::Lambda - AWS Lambda log source

=head1 SYNOPSIS

    use PerlText::Source::AWS::Lambda;

    my $source = PerlText::Source::AWS::Lambda->new(
        function_name => 'my-function',
        profile       => 'production',
        region        => 'us-east-1',
        limit         => 100,
    );

    # Fetch recent events
    my $events = $source->fetch_events(
        start_time => (time() - 3600) * 1000,  # Last hour in ms
    );

    # Get invocation statistics
    my $stats = $source->get_stats;

    # List invocations with their events
    my $invocations = $source->list_invocations;

=head1 DESCRIPTION

Fetches and parses AWS Lambda function logs from CloudWatch Logs.
Understands Lambda-specific log formats including START, END, REPORT
messages, and structured JSON logs.

=head1 ATTRIBUTES

=head2 function_name

Required. Name of the Lambda function.

=head2 profile

AWS CLI profile name.

=head2 region

AWS region.

=head2 limit

Maximum events to fetch. Default: 100.

=head2 filter_pattern

CloudWatch Logs filter pattern.

=head1 METHODS

=head2 fetch_events(%opts)

Fetch log events. Options:

=over 4

=item * start_time - Start timestamp in milliseconds

=item * end_time - End timestamp in milliseconds

=back

=head2 get_stats(%opts)

Get invocation statistics (duration, memory, cold starts).

=head2 list_invocations(%opts)

List recent invocations grouped by request ID.

=head1 PARSED FIELDS

=over 4

=item * type - Event type (start, end, report, log, error, structured)

=item * request_id - Lambda request ID

=item * duration - Execution duration in ms

=item * billed_duration - Billed duration in ms

=item * memory_size - Configured memory in MB

=item * max_memory_used - Peak memory usage in MB

=item * cold_start - Boolean indicating cold start

=item * init_duration - Cold start init duration in ms

=item * level - Log level

=item * message - Log message

=back

=cut
