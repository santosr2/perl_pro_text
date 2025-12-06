package Sift::Query::Executor;
use v5.36;
use Moo;
use Types::Standard qw(ArrayRef HashRef);
use Sift::Query::AST;
use namespace::autoclean;

has events => (
    is       => 'ro',
    isa      => ArrayRef,
    required => 1,
);

sub execute ($self, $ast) {
    my @result = $self->events->@*;

    # Apply WHERE filter
    if ($ast->where) {
        @result = grep { $self->_evaluate($_, $ast->where) } @result;
    }

    # Apply GROUP BY and aggregations
    if ($ast->group->@* || $ast->aggs->@*) {
        @result = $self->_aggregate(\@result, $ast->group, $ast->aggs);
    }

    # Apply SORT
    if ($ast->sort) {
        @result = $self->_sort(\@result, $ast->sort);
    }

    # Apply LIMIT
    if (defined $ast->limit) {
        @result = @result[0 .. ($ast->limit - 1)] if @result > $ast->limit;
    }

    return \@result;
}

sub _evaluate ($self, $event, $node) {
    my $type = $node->type;

    if ($type eq 'Comparison') {
        return $self->_eval_comparison($event, $node);
    }
    elsif ($type eq 'BinaryExpr') {
        my $left  = $self->_evaluate($event, $node->left);
        my $right = $self->_evaluate($event, $node->right);

        return $node->op eq 'AND' ? ($left && $right) : ($left || $right);
    }
    elsif ($type eq 'UnaryExpr') {
        return !$self->_evaluate($event, $node->operand);
    }
    elsif ($type eq 'InExpr') {
        my $value = $event->get($node->field);
        return 0 unless defined $value;
        return scalar grep { $self->_values_equal($value, $_) } $node->values->@*;
    }
    elsif ($type eq 'HasExpr') {
        return $event->has_field($node->field);
    }
    elsif ($type eq 'MatchExpr') {
        my $value = $event->get($node->field) // '';
        my $pattern = $node->pattern;
        return $value =~ /$pattern/;
    }

    return 0;
}

sub _eval_comparison ($self, $event, $node) {
    my $field_value = $event->get($node->field);
    my $compare_value = $node->value;
    my $op = $node->op;

    return 0 unless defined $field_value;

    # Numeric comparison
    if ($self->_is_numeric($field_value) && $self->_is_numeric($compare_value)) {
        return $self->_numeric_compare($field_value, $op, $compare_value);
    }

    # String comparison
    return $self->_string_compare($field_value, $op, $compare_value);
}

sub _numeric_compare ($self, $left, $op, $right) {
    return $left == $right if $op eq '==';
    return $left != $right if $op eq '!=';
    return $left >= $right if $op eq '>=';
    return $left <= $right if $op eq '<=';
    return $left >  $right if $op eq '>';
    return $left <  $right if $op eq '<';
    return 0;
}

sub _string_compare ($self, $left, $op, $right) {
    return $left eq $right if $op eq '==';
    return $left ne $right if $op eq '!=';
    return $left ge $right if $op eq '>=';
    return $left le $right if $op eq '<=';
    return $left gt $right if $op eq '>';
    return $left lt $right if $op eq '<';
    return 0;
}

sub _is_numeric ($self, $value) {
    return 0 unless defined $value;
    return $value =~ /^-?(?:\d+\.?\d*|\.\d+)$/;
}

sub _values_equal ($self, $a, $b) {
    if ($self->_is_numeric($a) && $self->_is_numeric($b)) {
        return $a == $b;
    }
    return $a eq $b;
}

sub _aggregate ($self, $events, $group_fields, $aggs) {
    return $events->@* unless $aggs->@*;

    my %groups;

    for my $event ($events->@*) {
        my $key = join("\x00", map { $event->get($_) // '' } $group_fields->@*);
        push $groups{$key}->@*, $event;
    }

    my @result;
    for my $key (keys %groups) {
        my @group_events = $groups{$key}->@*;
        my %row;

        # Include group fields
        my $sample = $group_events[0];
        for my $field ($group_fields->@*) {
            $row{$field} = $sample->get($field);
        }

        # Calculate aggregations
        for my $agg ($aggs->@*) {
            my $func  = $agg->func;
            my $field = $agg->field;

            if ($func eq 'count') {
                $row{count} = scalar @group_events;
            }
            elsif ($func eq 'sum') {
                $row{"sum_$field"} = $self->_sum(\@group_events, $field);
            }
            elsif ($func eq 'avg') {
                $row{"avg_$field"} = $self->_avg(\@group_events, $field);
            }
            elsif ($func eq 'min') {
                $row{"min_$field"} = $self->_min(\@group_events, $field);
            }
            elsif ($func eq 'max') {
                $row{"max_$field"} = $self->_max(\@group_events, $field);
            }
        }

        push @result, \%row;
    }

    return @result;
}

sub _sum ($self, $events, $field) {
    my $sum = 0;
    $sum += ($_->get($field) // 0) for $events->@*;
    return $sum;
}

sub _avg ($self, $events, $field) {
    return 0 unless $events->@*;
    return $self->_sum($events, $field) / scalar($events->@*);
}

sub _min ($self, $events, $field) {
    my @values = grep { defined } map { $_->get($field) } $events->@*;
    return undef unless @values;
    my $min = $values[0];
    $min = $_ < $min ? $_ : $min for @values;
    return $min;
}

sub _max ($self, $events, $field) {
    my @values = grep { defined } map { $_->get($field) } $events->@*;
    return undef unless @values;
    my $max = $values[0];
    $max = $_ > $max ? $_ : $max for @values;
    return $max;
}

sub _sort ($self, $items, $sort_spec) {
    my $field = $sort_spec->{field};
    my $desc  = ($sort_spec->{dir} // 'asc') eq 'desc';

    my @sorted = sort {
        my $av = ref $a eq 'HASH' ? $a->{$field} : $a->get($field);
        my $bv = ref $b eq 'HASH' ? $b->{$field} : $b->get($field);

        $av //= '';
        $bv //= '';

        my $cmp = $self->_is_numeric($av) && $self->_is_numeric($bv)
            ? $av <=> $bv
            : $av cmp $bv;

        $desc ? -$cmp : $cmp;
    } $items->@*;

    return @sorted;
}

1;

__END__

=head1 NAME

Sift::Query::Executor - Execute parsed queries against events

=head1 SYNOPSIS

    use Sift::Query::Executor;
    use Sift::Query::Parser;

    my $parser   = Sift::Query::Parser->new;
    my $ast      = $parser->parse('status >= 500 group by ip count');
    my $executor = Sift::Query::Executor->new(events => \@events);
    my $results  = $executor->execute($ast);

=head1 DESCRIPTION

Executes a parsed query AST against a collection of events, applying
filtering, grouping, aggregation, sorting, and limiting.

=head1 METHODS

=head2 execute($ast)

Execute the query and return results. Returns arrayref of events or
aggregation rows (hashrefs).

=cut
