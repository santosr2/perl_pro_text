package PerlText::Source::Azure::Monitor;
use v5.36;
use Moo;
use Types::Standard qw(Str Maybe Int);
use IPC::Run3;
use JSON::MaybeXS qw(decode_json);
use PerlText::Event;
use namespace::autoclean;

with 'PerlText::Source::Base';

has resource_group => (
    is  => 'ro',
    isa => Maybe[Str],
);

has subscription => (
    is  => 'ro',
    isa => Maybe[Str],
);

has resource_id => (
    is  => 'ro',
    isa => Maybe[Str],
);

has start_time => (
    is  => 'ro',
    isa => Maybe[Str],  # ISO8601 format
);

has end_time => (
    is  => 'ro',
    isa => Maybe[Str],
);

has max_events => (
    is      => 'ro',
    isa     => Int,
    default => 1000,
);

sub source_type ($self) { 'azure' }

sub _build_source_name ($self) {
    my $name = 'azure';
    $name .= ':' . $self->resource_group if $self->resource_group;
    return $name;
}

sub fetch_events ($self, %opts) {
    my @cmd = $self->_build_command(%opts);

    my ($stdout, $stderr);
    run3 \@cmd, undef, \$stdout, \$stderr;

    if ($?) {
        my $exit_code = $? >> 8;
        die "az monitor failed (exit $exit_code): $stderr\n" if $exit_code;
    }

    my $data = eval { decode_json($stdout) };
    return [] if $@ || !$data || ref $data ne 'ARRAY';

    my @events;
    for my $entry ($data->@*) {
        push @events, $self->_to_event($entry);
    }

    # Limit results
    @events = @events[0 .. $self->max_events - 1] if @events > $self->max_events;

    return \@events;
}

sub _build_command ($self, %opts) {
    my @cmd = (
        'az', 'monitor', 'activity-log', 'list',
        '--output', 'json',
    );

    push @cmd, '--subscription', $self->subscription if $self->subscription;
    push @cmd, '--resource-group', $self->resource_group if $self->resource_group;
    push @cmd, '--resource-id', $self->resource_id if $self->resource_id;
    push @cmd, '--start-time', $self->start_time if $self->start_time;
    push @cmd, '--end-time', $self->end_time if $self->end_time;
    push @cmd, '--max-events', $self->max_events;

    return @cmd;
}

sub _to_event ($self, $entry) {
    my $timestamp = $self->_parse_timestamp($entry->{eventTimestamp});

    my $fields = {
        level           => $entry->{level},
        operationName   => $entry->{operationName}{value} // $entry->{operationName},
        status          => $entry->{status}{value} // $entry->{status},
        caller          => $entry->{caller},
        correlationId   => $entry->{correlationId},
        eventDataId     => $entry->{eventDataId},
        resourceId      => $entry->{resourceId},
    };

    # Extract resource provider
    if (my $provider = $entry->{resourceProviderName}) {
        $fields->{resourceProvider} = $provider->{value} // $provider;
    }

    # Extract category
    if (my $category = $entry->{category}) {
        $fields->{category} = $category->{value} // $category;
    }

    # Extract properties
    if (my $props = $entry->{properties}) {
        for my $key (keys $props->%*) {
            $fields->{"prop.$key"} = $props->{$key};
        }
    }

    my $raw = $entry->{description} // '';

    return PerlText::Event->new(
        timestamp => $timestamp,
        source    => $self->source_name,
        raw       => $raw,
        fields    => $fields,
    );
}

sub _parse_timestamp ($self, $ts) {
    return time() unless $ts;

    # Azure timestamps are in ISO8601 format
    if ($ts =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/) {
        require Time::Local;
        my ($y, $m, $d, $h, $min, $s) = ($1, $2, $3, $4, $5, $6);
        return eval { Time::Local::timegm($s, $min, $h, $d, $m - 1, $y) } // time();
    }

    return time();
}

1;

__END__

=head1 NAME

PerlText::Source::Azure::Monitor - Fetch logs from Azure Monitor

=head1 SYNOPSIS

    use PerlText::Source::Azure::Monitor;

    my $source = PerlText::Source::Azure::Monitor->new(
        resource_group => 'my-rg',
        subscription   => 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
    );

    my $events = $source->fetch_events;

=head1 DESCRIPTION

Fetches activity logs from Azure Monitor using the az CLI.

=head1 ATTRIBUTES

=head2 resource_group

Azure resource group name.

=head2 subscription

Azure subscription ID.

=head2 resource_id

Specific resource ID.

=head2 start_time

Start time in ISO8601 format.

=head2 end_time

End time in ISO8601 format.

=head2 max_events

Maximum events. Default: 1000.

=cut
