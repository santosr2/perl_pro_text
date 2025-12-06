package Sift::Output::Chart;
use v5.36;
use Moo;
use Types::Standard qw(Str Int);
use Term::ANSIColor qw(colored);
use List::Util qw(max sum);
use namespace::autoclean;

with 'Sift::Output::Base';

has value_field => (
    is      => 'ro',
    isa     => Str,
    default => 'count',
);

has label_field => (
    is      => 'ro',
    isa     => Str,
    predicate => 'has_label_field',
);

has max_width => (
    is      => 'ro',
    isa     => Int,
    default => 50,
);

has color => (
    is      => 'ro',
    default => 1,
);

has bar_char => (
    is      => 'ro',
    default => '█',
);

has bar_partial => (
    is      => 'ro',
    default => sub { ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉'] },
);

sub format_name ($self) { 'chart' }

sub format ($self, $data) {
    my @items = $self->_extract_data($data);
    return "No data to chart\n" unless @items;

    my $max_value = max(map { $_->{value} } @items) || 1;
    my $max_label = max(map { length($_->{label}) } @items) || 1;

    my @lines;

    # Title
    push @lines, '';

    # Bars
    for my $item (@items) {
        my $bar = $self->_make_bar($item->{value}, $max_value);
        my $label = sprintf("%-${max_label}s", $item->{label});
        my $value = $self->_format_number($item->{value});

        if ($self->color) {
            $bar = colored($bar, $self->_bar_color($item->{value}, $max_value));
        }

        push @lines, sprintf("%s │%s %s", $label, $bar, $value);
    }

    # Footer with total if applicable
    my $total = sum(map { $_->{value} } @items);
    push @lines, '';
    push @lines, sprintf("Total: %s", $self->_format_number($total));
    push @lines, '';

    return join("\n", @lines);
}

sub _extract_data ($self, $data) {
    my @items;

    for my $item ($data->@*) {
        my ($label, $value);

        # Handle plain hashrefs (aggregation results) first
        if (ref $item eq 'HASH') {
            $value = $item->{$self->value_field} // 0;
            $label = $self->has_label_field
                ? ($item->{$self->label_field} // 'unknown')
                : $self->_make_label_from_hash($item);
        }
        # Handle Event objects
        elsif (ref $item && $item->can('get')) {
            $value = $item->get($self->value_field) // 0;
            $label = $self->has_label_field
                ? ($item->get($self->label_field) // 'unknown')
                : $self->_make_label_from_event($item);
        }
        else {
            next;
        }

        push @items, { label => $label, value => $value };
    }

    # Sort by value descending
    return sort { $b->{value} <=> $a->{value} } @items;
}

sub _make_label_from_event ($self, $event) {
    my %fields = $event->fields->%*;

    # Use first non-value field as label
    for my $key (sort keys %fields) {
        next if $key eq $self->value_field;
        next if $key =~ /^(timestamp|source|raw|format)$/;
        my $val = $fields{$key};
        return "$key=$val" if defined $val && !ref $val;
    }

    return 'item';
}

sub _make_label_from_hash ($self, $hash) {
    for my $key (sort keys %$hash) {
        next if $key eq $self->value_field;
        next if $key =~ /^(count|sum_|avg_|min_|max_)/;
        my $val = $hash->{$key};
        return $val if defined $val && !ref $val;
    }
    return 'item';
}

sub _make_bar ($self, $value, $max_value) {
    my $ratio = $value / $max_value;
    my $width = $ratio * $self->max_width;

    my $full_blocks = int($width);
    my $partial_idx = int(($width - $full_blocks) * 8);

    my $bar = $self->bar_char x $full_blocks;
    $bar .= $self->bar_partial->[$partial_idx] if $partial_idx > 0;

    # Pad to consistent width
    my $display_width = length($bar);
    $bar .= ' ' x ($self->max_width - $display_width) if $display_width < $self->max_width;

    return $bar;
}

sub _bar_color ($self, $value, $max_value) {
    my $ratio = $value / $max_value;

    return 'green'  if $ratio < 0.25;
    return 'cyan'   if $ratio < 0.50;
    return 'yellow' if $ratio < 0.75;
    return 'red';
}

sub _format_number ($self, $value) {
    return '0' unless defined $value;

    # Format large numbers with K/M suffix
    if ($value >= 1_000_000) {
        return sprintf("%.1fM", $value / 1_000_000);
    }
    elsif ($value >= 1_000) {
        return sprintf("%.1fK", $value / 1_000);
    }
    elsif ($value == int($value)) {
        return $value;
    }
    else {
        return sprintf("%.2f", $value);
    }
}

1;

__END__

=head1 NAME

Sift::Output::Chart - ASCII bar chart output

=head1 SYNOPSIS

    use Sift::Output::Chart;

    my $formatter = Sift::Output::Chart->new(
        value_field => 'count',
        label_field => 'ip',
        max_width   => 40,
    );

    print $formatter->format($aggregated_results);

=head1 DESCRIPTION

Renders aggregated data as ASCII horizontal bar charts with optional
color coding.

=head1 ATTRIBUTES

=head2 value_field

Field to use for bar values. Default: 'count'

=head2 label_field

Field to use for labels. If not specified, auto-detects from data.

=head2 max_width

Maximum bar width in characters. Default: 50

=head2 color

Enable/disable colors. Default: 1

=head1 EXAMPLE OUTPUT

    192.168.1.1   │████████████████████████████████ 1523
    192.168.1.2   │██████████████████               856
    192.168.1.3   │███████████                      512
    10.0.0.5      │███                              145

    Total: 3036

=cut
