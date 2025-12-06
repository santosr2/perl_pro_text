package Sift::Transform::Aggregator;
use v5.36;
use Moo;
use Types::Standard qw(ArrayRef Str);
use List::Util qw(sum min max);
use namespace::autoclean;

has group_by => (
    is      => 'ro',
    isa     => ArrayRef[Str],
    default => sub { [] },
);

has aggregations => (
    is      => 'ro',
    isa     => ArrayRef,
    default => sub { [] },
);

sub aggregate ($self, $events) {
    my %groups;

    # Group events
    for my $event ($events->@*) {
        my $key = $self->_make_group_key($event);
        push $groups{$key}->@*, $event;
    }

    # Apply aggregations to each group
    my @results;
    for my $key (sort keys %groups) {
        my $group_events = $groups{$key};
        my %result;

        # Add group-by field values
        if ($self->group_by->@* && $group_events->@*) {
            my $sample = $group_events->[0];
            for my $field ($self->group_by->@*) {
                $result{$field} = $sample->get($field);
            }
        }

        # Apply each aggregation
        for my $agg ($self->aggregations->@*) {
            my ($name, $value) = $self->_apply_agg($agg, $group_events);
            $result{$name} = $value;
        }

        push @results, \%result;
    }

    return \@results;
}

sub _make_group_key ($self, $event) {
    return '_all_' unless $self->group_by->@*;

    my @parts;
    for my $field ($self->group_by->@*) {
        my $val = $event->get($field) // '';
        push @parts, "$field=$val";
    }
    return join('|', @parts);
}

sub _apply_agg ($self, $agg, $events) {
    my $func  = $agg->func;
    my $field = $agg->field;

    if ($func eq 'count') {
        return ('count', scalar($events->@*));
    }
    elsif ($func eq 'sum') {
        my @values = map { $_->get($field) // 0 } $events->@*;
        return ("sum_$field", sum(@values) // 0);
    }
    elsif ($func eq 'avg') {
        my @values = map { $_->get($field) // 0 } $events->@*;
        my $avg = @values ? sum(@values) / @values : 0;
        return ("avg_$field", $avg);
    }
    elsif ($func eq 'min') {
        my @values = map { $_->get($field) } grep { defined $_->get($field) } $events->@*;
        return ("min_$field", @values ? min(@values) : undef);
    }
    elsif ($func eq 'max') {
        my @values = map { $_->get($field) } grep { defined $_->get($field) } $events->@*;
        return ("max_$field", @values ? max(@values) : undef);
    }

    return ($func, undef);
}

1;

__END__

=head1 NAME

Sift::Transform::Aggregator - Group and aggregate events

=head1 SYNOPSIS

    use Sift::Transform::Aggregator;
    use Sift::Query::AST;

    my $agg = Sift::Transform::Aggregator->new(
        group_by     => ['ip'],
        aggregations => [
            Sift::Query::AST::Aggregation->new(func => 'count'),
            Sift::Query::AST::Aggregation->new(func => 'avg', field => 'bytes'),
        ],
    );

    my $results = $agg->aggregate($events);
    # Returns arrayref of hashrefs with group key + aggregation values

=head1 DESCRIPTION

Groups events by field values and computes aggregations like count,
sum, avg, min, max.

=head1 SUPPORTED AGGREGATIONS

=over 4

=item * count - Count of events in group

=item * sum - Sum of numeric field

=item * avg - Average of numeric field

=item * min - Minimum value

=item * max - Maximum value

=back

=cut
