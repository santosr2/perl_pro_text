package Sift::Source::Stdin;
use v5.36;
use Moo;
use Types::Standard qw(Bool FileHandle);
use Sift::Parser::Detector;
use namespace::autoclean;

with 'Sift::Source::Base';

has '+is_streaming' => (default => 1);

has detector => (
    is      => 'lazy',
    default => sub { Sift::Parser::Detector->new },
);

has _fh => (
    is      => 'ro',
    default => sub { \*STDIN },
);

has _buffer => (
    is      => 'rw',
    default => sub { [] },
);

has _parser => (
    is        => 'rw',
    predicate => '_has_parser',
);

has _detected => (
    is      => 'rw',
    default => 0,
);

sub source_type ($self) { 'stdin' }

sub fetch_events ($self, %opts) {
    my @events;
    my $limit = $opts{limit};
    my $fh    = $self->_fh;

    # Read all available lines
    my @lines;
    while (my $line = <$fh>) {
        chomp $line;
        push @lines, $line if $line =~ /\S/;
    }

    return [] unless @lines;

    # Detect format from first lines if not already done
    unless ($self->_detected) {
        my @sample = @lines[0 .. min(9, $#lines)];
        my $parser = $self->detector->detect(\@sample);
        $self->_parser($parser);
        $self->_detected(1);
    }

    return [] unless $self->_parser;

    # Parse all lines
    for my $line (@lines) {
        my $event = $self->_parser->parse($line, '-');
        if ($event) {
            push @events, $event;
            last if $limit && @events >= $limit;
        }
    }

    return \@events;
}

sub next_event ($self) {
    my $fh = $self->_fh;

    # Read next line
    my $line = <$fh>;
    return undef unless defined $line;
    chomp $line;
    return undef unless $line =~ /\S/;

    # Detect format if first line
    unless ($self->_detected) {
        push $self->_buffer->@*, $line;

        # Need at least a few lines to detect
        if ($self->_buffer->@* >= 3) {
            my $parser = $self->detector->detect($self->_buffer);
            $self->_parser($parser);
            $self->_detected(1);

            # Process buffered lines
            my @events;
            for my $buffered ($self->_buffer->@*) {
                my $event = $self->_parser->parse($buffered, '-');
                push @events, $event if $event;
            }
            $self->_buffer([]);
            return @events;
        }
        return ();
    }

    return $self->_parser->parse($line, '-');
}

sub has_more ($self) {
    return !eof($self->_fh);
}

sub min ($a, $b) { $a < $b ? $a : $b }

1;

__END__

=head1 NAME

Sift::Source::Stdin - Read log events from standard input

=head1 SYNOPSIS

    use Sift::Source::Stdin;

    my $source = Sift::Source::Stdin->new;

    # Batch mode
    my $events = $source->fetch_events;

    # Streaming mode
    while ($source->has_more) {
        my $event = $source->next_event;
        # process event
    }

=head1 DESCRIPTION

Reads log lines from STDIN, auto-detects format, and converts to events.
Supports both batch and streaming modes.

=head1 METHODS

=head2 fetch_events(%opts)

Read all available input and return events.

=head2 next_event

Read and return the next event (streaming mode).

=head2 has_more

Returns true if more input is available.

=cut
