package Sift::Output::CSV;
use v5.36;
use Moo;
use Text::CSV_XS;
use namespace::autoclean;

with 'Sift::Output::Base';

has include_header => (
    is      => 'ro',
    default => 1,
);

has csv => (
    is      => 'lazy',
    builder => '_build_csv',
);

sub _build_csv ($self) {
    return Text::CSV_XS->new({
        binary    => 1,
        auto_diag => 1,
        eol       => "\n",
    });
}

sub format ($self, $items) {
    return '' unless $items && $items->@*;

    my @columns = $self->extract_columns($items);
    return '' unless @columns;

    my $output = '';

    # Header row
    if ($self->include_header) {
        $self->csv->combine(@columns);
        $output .= $self->csv->string;
    }

    # Data rows
    for my $item ($items->@*) {
        my $hash = $self->format_event($item);
        my @row  = map { $self->_format_value($hash->{$_}) } @columns;
        $self->csv->combine(@row);
        $output .= $self->csv->string;
    }

    return $output;
}

sub _format_value ($self, $value) {
    return '' unless defined $value;

    if (ref $value eq 'ARRAY') {
        return join(';', $value->@*);
    }
    if (ref $value eq 'HASH') {
        return join(';', map { "$_=$value->{$_}" } sort keys $value->%*);
    }

    return "$value";
}

1;

__END__

=head1 NAME

Sift::Output::CSV - CSV output formatter

=head1 SYNOPSIS

    use Sift::Output::CSV;

    my $formatter = Sift::Output::CSV->new;
    print $formatter->format(\@events);

=head1 ATTRIBUTES

=head2 include_header

Include header row. Default: true.

=cut
