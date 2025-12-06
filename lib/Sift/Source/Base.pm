package Sift::Source::Base;
use v5.36;
use Moo::Role;
use Types::Standard qw(Str Bool);
use namespace::autoclean;

requires 'fetch_events';
requires 'source_type';

has source_name => (
    is      => 'ro',
    isa     => Str,
    lazy    => 1,
    builder => '_build_source_name',
);

has is_streaming => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

sub _build_source_name ($self) {
    return $self->source_type;
}

sub get_events ($self, %opts) {
    return $self->fetch_events(%opts);
}

1;

__END__

=head1 NAME

Sift::Source::Base - Base role for log sources

=head1 DESCRIPTION

Base role that all log sources must consume.

=head1 REQUIRED METHODS

=head2 fetch_events(%opts)

Fetch events from the source. Returns arrayref of Sift::Event objects.

=head2 source_type

Return a string identifier for this source type (e.g., 'file', 'k8s', 'aws').

=cut
