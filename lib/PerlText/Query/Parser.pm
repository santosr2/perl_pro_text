package PerlText::Query::Parser;
use v5.36;
use Moo;
use Marpa::R2;
use PerlText::Query::Grammar;
use PerlText::Query::AST;
use namespace::autoclean;

has grammar => (
    is      => 'lazy',
    default => sub { PerlText::Query::Grammar->new->grammar },
);

sub parse ($self, $query_string) {
    my $recce = Marpa::R2::Scanless::R->new({
        grammar         => $self->grammar,
        semantics_package => 'PerlText::Query::Parser::Actions',
    });

    eval { $recce->read(\$query_string) };
    if ($@) {
        my $error = $@;
        die "Parse error: $error\n";
    }

    my $value_ref = $recce->value;
    die "No parse result\n" unless defined $value_ref;

    return $$value_ref;
}

sub parse_or_die ($self, $query_string) {
    return $self->parse($query_string);
}

sub try_parse ($self, $query_string) {
    my $result = eval { $self->parse($query_string) };
    return $@ ? (undef, $@) : ($result, undef);
}

package PerlText::Query::Parser::Actions {
    use v5.36;

    sub new ($class, @args) {
        return bless {}, $class;
    }

    # Helper actions
    sub do_args  { shift; return [@_] }
    sub do_first { shift; return $_[0] }
    sub do_empty { return undef }
    sub do_none  { return undef }

    # Query builder
    sub build_query ($self, $where, $group, $aggs, $sort, $limit) {
        return PerlText::Query::AST::Query->new(
            sources => [],
            where   => $where,
            group   => $group // [],
            aggs    => $aggs  // [],
            sort    => $sort,
            limit   => $limit,
        );
    }

    # WHERE clause
    sub where_clause ($self, $kw, $expr) {
        return $expr;
    }

    sub where_clause_implicit ($self, $expr) {
        return $expr;
    }

    # Expressions
    sub or_expr ($self, $left, $kw, $right) {
        return PerlText::Query::AST::BinaryExpr->new(
            op    => 'OR',
            left  => $left,
            right => $right,
        );
    }

    sub and_expr ($self, $left, $kw, $right) {
        return PerlText::Query::AST::BinaryExpr->new(
            op    => 'AND',
            left  => $left,
            right => $right,
        );
    }

    sub not_expr ($self, $kw, $operand) {
        return PerlText::Query::AST::UnaryExpr->new(
            op      => 'NOT',
            operand => $operand,
        );
    }

    sub paren_expr ($self, $lp, $expr, $rp) {
        return $expr;
    }

    # Comparisons
    sub comparison ($self, $field, $op, $value) {
        return PerlText::Query::AST::Comparison->new(
            field => $field,
            op    => $op,
            value => $value,
        );
    }

    sub op_eq ($self, @args) { '==' }
    sub op_ne ($self, @args) { '!=' }
    sub op_ge ($self, @args) { '>=' }
    sub op_le ($self, @args) { '<=' }
    sub op_gt ($self, @args) { '>'  }
    sub op_lt ($self, @args) { '<'  }

    # IN expression
    sub in_expr ($self, $field, $kw, $lb, $values, $rb) {
        return PerlText::Query::AST::InExpr->new(
            field  => $field,
            values => $values,
        );
    }

    sub value_list ($self, @values) {
        return [ grep { defined } @values ];
    }

    # GROUP BY
    sub group_clause ($self, $kw_group, $kw_by, $fields) {
        return $fields;
    }

    sub group_clause_short ($self, $kw_group, $fields) {
        return $fields;
    }

    sub field_list ($self, @fields) {
        return [ grep { defined } @fields ];
    }

    # Aggregations
    sub agg_clauses ($self, @aggs) {
        return [ grep { defined } @aggs ];
    }

    sub count_agg ($self, @args) {
        return PerlText::Query::AST::Aggregation->new(func => 'count');
    }

    sub avg_agg ($self, $kw, $field) {
        return PerlText::Query::AST::Aggregation->new(func => 'avg', field => $field);
    }

    sub sum_agg ($self, $kw, $field) {
        return PerlText::Query::AST::Aggregation->new(func => 'sum', field => $field);
    }

    sub min_agg ($self, $kw, $field) {
        return PerlText::Query::AST::Aggregation->new(func => 'min', field => $field);
    }

    sub max_agg ($self, $kw, $field) {
        return PerlText::Query::AST::Aggregation->new(func => 'max', field => $field);
    }

    # SORT clause
    sub sort_clause ($self, $kw_sort, $kw_by, $field, $dir) {
        return { field => $field, dir => $dir // 'asc' };
    }

    sub sort_clause_short ($self, $kw_sort, $field, $dir) {
        return { field => $field, dir => $dir // 'asc' };
    }

    sub sort_asc  ($self, @args) { 'asc' }
    sub sort_desc ($self, @args) { 'desc' }

    # LIMIT clause
    sub limit_clause ($self, $kw, $n) {
        return $n;
    }

    # Values
    sub field ($self, $ident) {
        return $ident;
    }

    sub dq_string ($self, $s) {
        $s =~ s/^"//;
        $s =~ s/"$//;
        return $s;
    }

    sub sq_string ($self, $s) {
        $s =~ s/^'//;
        $s =~ s/'$//;
        return $s;
    }

    sub integer ($self, $n) {
        return 0 + $n;
    }

    sub float ($self, $n) {
        return 0.0 + $n;
    }

    sub do_string ($self, $s) {
        $s =~ s/^["']//;
        $s =~ s/["']$//;
        return $s;
    }

    sub do_number ($self, $n) {
        return 0 + $n;
    }
}

1;

__END__

=head1 NAME

PerlText::Query::Parser - Parse query strings into AST

=head1 SYNOPSIS

    use PerlText::Query::Parser;

    my $parser = PerlText::Query::Parser->new;

    my $ast = $parser->parse('status >= 500 and service == "auth"');

    # With error handling
    my ($ast, $error) = $parser->try_parse($query);
    die $error if $error;

=head1 DESCRIPTION

Parses PerlText query language strings into an AST using Marpa::R2.

=head1 METHODS

=head2 parse($query_string)

Parse query and return AST. Dies on parse error.

=head2 try_parse($query_string)

Parse query and return ($ast, undef) or (undef, $error).

=head2 parse_or_die($query_string)

Alias for parse().

=cut
