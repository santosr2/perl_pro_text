package Sift::Output::Pretty;
use v5.36;
use Moo;
use Term::ANSIColor qw(colored);
use namespace::autoclean;

with 'Sift::Output::Base';

has show_raw => (
    is      => 'ro',
    default => 0,
);

has color => (
    is      => 'ro',
    default => 1,
);

# Color schemes for different field types
my %LEVEL_COLORS = (
    error    => 'bold red',
    err      => 'bold red',
    critical => 'bold red',
    crit     => 'bold red',
    fatal    => 'bold red',
    emerg    => 'bold red',
    alert    => 'bold red',
    warning  => 'yellow',
    warn     => 'yellow',
    notice   => 'cyan',
    info     => 'green',
    debug    => 'blue',
);

my %STATUS_COLORS = (
    '2xx' => 'green',
    '3xx' => 'cyan',
    '4xx' => 'yellow',
    '5xx' => 'bold red',
);

sub format_name ($self) { 'pretty' }

sub format ($self, $events) {
    my @lines;
    for my $event ($events->@*) {
        push @lines, $self->format_single($event);
        push @lines, '';  # Blank line separator
    }
    return join("\n", @lines);
}

sub format_single ($self, $event) {
    my @lines;

    # Handle plain hashrefs (from aggregations)
    if (ref $event eq 'HASH') {
        return $self->_format_hashref($event);
    }

    # Header line with timestamp and source
    my $header = sprintf("[%s] %s",
        $self->format_timestamp($event->timestamp),
        $event->source,
    );
    push @lines, $self->_colorize($header, 'bold white');

    # Fields
    my %fields = $event->fields->%*;

    # Show level/severity prominently if present
    for my $level_field (qw(level severity)) {
        if (my $level = delete $fields{$level_field}) {
            my $color = $LEVEL_COLORS{lc($level)} // 'white';
            push @lines, sprintf("  %s: %s",
                $level_field,
                $self->_colorize(uc($level), $color),
            );
        }
    }

    # Show message prominently if present
    if (my $message = delete $fields{message}) {
        push @lines, sprintf("  message: %s", $message);
    }

    # Show status with color
    if (my $status = delete $fields{status}) {
        my $color = $self->_status_color($status);
        push @lines, sprintf("  status: %s", $self->_colorize($status, $color));
    }

    # Other fields
    for my $key (sort keys %fields) {
        my $value = $fields{$key};
        next unless defined $value;
        $value = $self->_format_value($value);
        push @lines, sprintf("  %s: %s", $key, $value);
    }

    # Raw line if requested
    if ($self->show_raw && $event->raw) {
        push @lines, $self->_colorize("  raw: " . $event->raw, 'dark');
    }

    return join("\n", @lines);
}

sub _format_hashref ($self, $hash) {
    my @lines;
    for my $key (sort keys %$hash) {
        my $value = $hash->{$key} // '';
        push @lines, sprintf("  %s: %s", $key, $value);
    }
    return join("\n", @lines);
}

sub _format_value ($self, $value) {
    return 'null' unless defined $value;

    if (ref $value eq 'ARRAY') {
        return '[' . join(', ', map { $self->_format_value($_) } @$value) . ']';
    }
    elsif (ref $value eq 'HASH') {
        return '{...}';
    }

    return $value;
}

sub _status_color ($self, $status) {
    return 'white' unless $status =~ /^\d+$/;

    if ($status >= 500) { return $STATUS_COLORS{'5xx'} }
    if ($status >= 400) { return $STATUS_COLORS{'4xx'} }
    if ($status >= 300) { return $STATUS_COLORS{'3xx'} }
    if ($status >= 200) { return $STATUS_COLORS{'2xx'} }
    return 'white';
}

sub _colorize ($self, $text, $color) {
    return $text unless $self->color;
    return colored($text, $color);
}

1;

__END__

=head1 NAME

Sift::Output::Pretty - Human-readable colored output

=head1 SYNOPSIS

    use Sift::Output::Pretty;

    my $formatter = Sift::Output::Pretty->new(
        color    => 1,
        show_raw => 0,
    );

    print $formatter->format($events);

=head1 DESCRIPTION

Formats log events in a human-readable format with color highlighting:

=over 4

=item * Error levels in red

=item * Warnings in yellow

=item * HTTP 5xx status in bold red

=item * HTTP 4xx status in yellow

=item * HTTP 2xx status in green

=back

=head1 ATTRIBUTES

=head2 color

Enable/disable color output. Default: 1 (enabled)

=head2 show_raw

Include the raw log line. Default: 0

=cut
