package PerlText::Parser::Base;
use v5.36;
use Moo::Role;
use Types::Standard qw(Str ArrayRef);
use namespace::autoclean;

requires 'parse';
requires 'can_parse';
requires 'format_name';

has source_name => (
    is      => 'ro',
    isa     => Str,
    default => 'unknown',
);

sub parse_line ($self, $line, $source = undef) {
    $source //= $self->source_name;
    return $self->parse($line, $source);
}

sub parse_lines ($self, $lines, $source = undef) {
    my @events;
    for my $line ($lines->@*) {
        my $event = $self->parse_line($line, $source);
        push @events, $event if $event;
    }
    return \@events;
}

sub confidence_score ($self, $sample_lines) {
    my $total   = scalar $sample_lines->@*;
    return 0 unless $total;

    my $matched = 0;
    for my $line ($sample_lines->@*) {
        $matched++ if $self->can_parse($line);
    }

    return $matched / $total;
}

1;

__END__

=head1 NAME

PerlText::Parser::Base - Base role for log format parsers

=head1 SYNOPSIS

    package PerlText::Parser::MyFormat;
    use Moo;
    with 'PerlText::Parser::Base';

    sub format_name { 'myformat' }

    sub can_parse ($self, $line) {
        return $line =~ /^MYFORMAT:/;
    }

    sub parse ($self, $line, $source) {
        # Parse and return PerlText::Event
    }

=head1 DESCRIPTION

Base role that all log format parsers must consume. Provides common
functionality and requires implementation of core parsing methods.

=head1 REQUIRED METHODS

=head2 parse($line, $source)

Parse a log line and return a PerlText::Event object, or undef if unparseable.

=head2 can_parse($line)

Return true if this parser can handle the given line format.

=head2 format_name

Return a string identifier for this log format (e.g., 'nginx', 'json').

=head1 PROVIDED METHODS

=head2 parse_line($line, $source?)

Convenience wrapper around parse() that uses default source_name.

=head2 parse_lines($lines_arrayref, $source?)

Parse multiple lines, returning arrayref of successfully parsed events.

=head2 confidence_score($sample_lines)

Calculate a 0.0-1.0 confidence score for how well this parser matches
the sample lines. Used by Detector for auto-detection.

=cut
