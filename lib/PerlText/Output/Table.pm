package PerlText::Output::Table;
use v5.36;
use Moo;
use Text::Table::Tiny qw(generate_table);
use Term::ANSIColor qw(colored);
use namespace::autoclean;

with 'PerlText::Output::Base';

has max_width => (
    is      => 'ro',
    default => 50,
);

has color => (
    is      => 'ro',
    default => 1,
);

sub format ($self, $items) {
    return '' unless $items && $items->@*;

    my @columns = $self->extract_columns($items);
    return '' unless @columns;

    my @rows;

    # Header row
    push @rows, \@columns;

    # Data rows
    for my $item ($items->@*) {
        my $hash = $self->format_event($item);
        my @row  = map { $self->_format_value($hash->{$_}, $_) } @columns;
        push @rows, \@row;
    }

    my $table = generate_table(
        rows       => \@rows,
        header_row => 1,
        style      => 'boxrule',
    );

    return $table . "\n";
}

sub _format_value ($self, $value, $column) {
    return '' unless defined $value;

    # Format based on column type
    if ($column eq 'timestamp') {
        return $self->_format_timestamp($value);
    }

    # Truncate long values
    my $str = ref $value ? $self->_stringify($value) : "$value";
    if (length($str) > $self->max_width) {
        $str = substr($str, 0, $self->max_width - 3) . '...';
    }

    # Color code certain values
    if ($self->color && $column eq 'status') {
        return $self->_color_status($str);
    }

    if ($self->color && $column eq 'level') {
        return $self->_color_level($str);
    }

    return $str;
}

sub _format_timestamp ($self, $ts) {
    my @t = localtime($ts);
    return sprintf('%04d-%02d-%02d %02d:%02d:%02d',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

sub _stringify ($self, $value) {
    if (ref $value eq 'ARRAY') {
        return '[' . join(', ', $value->@*) . ']';
    }
    if (ref $value eq 'HASH') {
        return '{' . join(', ', map { "$_: $value->{$_}" } keys $value->%*) . '}';
    }
    return "$value";
}

sub _color_status ($self, $status) {
    return $status unless $status =~ /^\d+$/;
    my $code = int($status);

    return colored(['green'],  $status) if $code >= 200 && $code < 300;
    return colored(['yellow'], $status) if $code >= 300 && $code < 400;
    return colored(['red'],    $status) if $code >= 400 && $code < 500;
    return colored(['bold red'], $status) if $code >= 500;
    return $status;
}

sub _color_level ($self, $level) {
    my $lc = lc $level;
    return colored(['red'],    $level) if $lc =~ /^(error|err|crit|emerg|fatal)$/;
    return colored(['yellow'], $level) if $lc =~ /^(warn|warning)$/;
    return colored(['cyan'],   $level) if $lc =~ /^(info)$/;
    return colored(['white'],  $level) if $lc =~ /^(debug)$/;
    return $level;
}

1;

__END__

=head1 NAME

PerlText::Output::Table - ASCII table output formatter

=head1 SYNOPSIS

    use PerlText::Output::Table;

    my $formatter = PerlText::Output::Table->new;
    print $formatter->format(\@events);

=head1 DESCRIPTION

Formats events as a pretty ASCII table with optional color coding
for status codes and log levels.

=cut
