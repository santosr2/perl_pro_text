package PerlText::Source::AWS::CloudWatch;
use v5.36;
use Moo;
use Types::Standard qw(Str Maybe Int);
use IPC::Run3;
use JSON::MaybeXS qw(decode_json);
use PerlText::Event;
use namespace::autoclean;

with 'PerlText::Source::Base';

has log_group => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has log_stream => (
    is  => 'ro',
    isa => Maybe[Str],
);

has filter_pattern => (
    is      => 'ro',
    isa     => Str,
    default => '',
);

has profile => (
    is      => 'ro',
    isa     => Str,
    default => 'default',
);

has region => (
    is  => 'ro',
    isa => Maybe[Str],
);

has start_time => (
    is  => 'ro',
    isa => Maybe[Int],  # Unix timestamp in milliseconds
);

has end_time => (
    is  => 'ro',
    isa => Maybe[Int],
);

has limit => (
    is      => 'ro',
    isa     => Int,
    default => 1000,
);

sub source_type ($self) { 'aws' }

sub _build_source_name ($self) {
    return 'aws:' . $self->log_group;
}

sub fetch_events ($self, %opts) {
    my @cmd = $self->_build_command(%opts);

    my ($stdout, $stderr);
    run3 \@cmd, undef, \$stdout, \$stderr;

    if ($?) {
        my $exit_code = $? >> 8;
        die "aws logs failed (exit $exit_code): $stderr\n" if $exit_code;
    }

    my $data = eval { decode_json($stdout) };
    return [] if $@ || !$data;

    my @events;
    for my $event ($data->{events}->@*) {
        push @events, $self->_to_event($event);
    }

    return \@events;
}

sub _build_command ($self, %opts) {
    my @cmd = (
        'aws', 'logs', 'filter-log-events',
        '--log-group-name', $self->log_group,
        '--output', 'json',
    );

    push @cmd, '--profile', $self->profile if $self->profile;
    push @cmd, '--region', $self->region if $self->region;
    push @cmd, '--log-stream-names', $self->log_stream if $self->log_stream;
    push @cmd, '--filter-pattern', $self->filter_pattern if $self->filter_pattern;
    push @cmd, '--limit', $self->limit;

    my $start = $opts{start_time} // $self->start_time;
    my $end   = $opts{end_time}   // $self->end_time;

    push @cmd, '--start-time', $start if defined $start;
    push @cmd, '--end-time', $end if defined $end;

    return @cmd;
}

sub _to_event ($self, $cw_event) {
    my $message   = $cw_event->{message} // '';
    my $timestamp = int(($cw_event->{timestamp} // 0) / 1000);  # ms to seconds

    # Try to parse as JSON
    my $fields = {};
    if ($message =~ /^\s*\{/) {
        my $parsed = eval { decode_json($message) };
        if ($parsed && ref $parsed eq 'HASH') {
            $fields = $self->_flatten($parsed);
        }
    }

    # Add CloudWatch metadata
    $fields->{logStreamName} = $cw_event->{logStreamName} if $cw_event->{logStreamName};
    $fields->{eventId}       = $cw_event->{eventId} if $cw_event->{eventId};

    return PerlText::Event->new(
        timestamp => $timestamp,
        source    => $self->source_name,
        raw       => $message,
        fields    => $fields,
    );
}

sub _flatten ($self, $data, $prefix = '') {
    my %fields;

    for my $key (keys $data->%*) {
        my $full_key = $prefix ? "${prefix}.${key}" : $key;
        my $value    = $data->{$key};

        if (ref $value eq 'HASH') {
            my %nested = $self->_flatten($value, $full_key);
            %fields = (%fields, %nested);
        }
        elsif (ref $value eq 'ARRAY') {
            $fields{$full_key} = $value;
        }
        else {
            $fields{$full_key} = $value;
        }
    }

    return %fields;
}

1;

__END__

=head1 NAME

PerlText::Source::AWS::CloudWatch - Fetch logs from AWS CloudWatch

=head1 SYNOPSIS

    use PerlText::Source::AWS::CloudWatch;

    my $source = PerlText::Source::AWS::CloudWatch->new(
        log_group => '/aws/lambda/my-function',
        profile   => 'production',
        region    => 'us-east-1',
    );

    my $events = $source->fetch_events(
        start_time => time() * 1000 - 3600000,  # Last hour
    );

=head1 DESCRIPTION

Fetches logs from AWS CloudWatch Logs using the AWS CLI.

=head1 ATTRIBUTES

=head2 log_group

Required. CloudWatch log group name.

=head2 log_stream

Optional. Specific log stream name.

=head2 filter_pattern

CloudWatch filter pattern.

=head2 profile

AWS CLI profile. Default: 'default'.

=head2 region

AWS region.

=head2 start_time

Start time in milliseconds since epoch.

=head2 end_time

End time in milliseconds since epoch.

=head2 limit

Maximum events to return. Default: 1000.

=cut
