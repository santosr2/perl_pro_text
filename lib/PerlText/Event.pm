package PerlText::Event;
use v5.36;
use Moo;
use Types::Standard qw(Str HashRef Maybe Num);
use namespace::autoclean;

has timestamp => (
    is       => 'ro',
    isa      => Num,
    required => 1,
);

has source => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has fields => (
    is      => 'rw',
    isa     => HashRef,
    default => sub { {} },
);

has raw => (
    is  => 'ro',
    isa => Maybe[Str],
);

sub get ($self, $key) {
    return $self->fields->{$key};
}

sub set ($self, $key, $value) {
    $self->fields->{$key} = $value;
    return $self;
}

sub has_field ($self, $key) {
    return exists $self->fields->{$key};
}

sub field_names ($self) {
    return keys $self->fields->%*;
}

sub to_hash ($self) {
    return {
        timestamp => $self->timestamp,
        source    => $self->source,
        $self->fields->%*,
    };
}

sub clone ($self, %overrides) {
    return __PACKAGE__->new(
        timestamp => $overrides{timestamp} // $self->timestamp,
        source    => $overrides{source}    // $self->source,
        fields    => $overrides{fields}    // { $self->fields->%* },
        raw       => $overrides{raw}       // $self->raw,
    );
}

1;

__END__

=head1 NAME

PerlText::Event - Unified log event representation

=head1 SYNOPSIS

    use PerlText::Event;

    my $event = PerlText::Event->new(
        timestamp => time(),
        source    => 'nginx',
        fields    => {
            status => 200,
            method => 'GET',
            path   => '/api/users',
        },
        raw => '192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /api/users HTTP/1.1" 200 1234',
    );

    say $event->get('status');       # 200
    $event->set('latency', 42);
    say $event->has_field('method'); # 1

=head1 DESCRIPTION

PerlText::Event represents a unified log event with a timestamp, source,
and arbitrary fields extracted from the log line.

=head1 ATTRIBUTES

=head2 timestamp

Unix timestamp (epoch seconds) of when the event occurred. Required.

=head2 source

String identifier for the log source (e.g., 'nginx', 'k8s', 'cloudwatch'). Required.

=head2 fields

HashRef of extracted field name/value pairs. Defaults to empty hash.

=head2 raw

Optional raw log line string.

=head1 METHODS

=head2 get($key)

Get a field value by name.

=head2 set($key, $value)

Set a field value. Returns $self for chaining.

=head2 has_field($key)

Returns true if the field exists.

=head2 field_names

Returns list of all field names.

=head2 to_hash

Returns a hashref with timestamp, source, and all fields merged.

=head2 clone(%overrides)

Create a copy of the event with optional overrides.

=cut
