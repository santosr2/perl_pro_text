package Sift::Query::AST;
use v5.36;
use Moo;
use Types::Standard qw(Str ArrayRef HashRef Maybe Any);
use namespace::autoclean;

# Base AST Node
package Sift::Query::AST::Node {
    use v5.36;
    use Moo;
    use namespace::autoclean;

    has type => (is => 'ro', required => 1);

    sub to_hash ($self) {
        return { type => $self->type };
    }
}

# Query node - top level
package Sift::Query::AST::Query {
    use v5.36;
    use Moo;
    use Types::Standard qw(ArrayRef Maybe InstanceOf);
    extends 'Sift::Query::AST::Node';
    use namespace::autoclean;

    has '+type' => (default => 'Query');
    has sources => (is => 'ro', isa => ArrayRef, default => sub { [] });
    has where   => (is => 'ro', isa => Maybe[InstanceOf['Sift::Query::AST::Node']]);
    has group   => (is => 'ro', isa => ArrayRef, default => sub { [] });
    has aggs    => (is => 'ro', isa => ArrayRef, default => sub { [] });
    has eval    => (is => 'ro');
    has sort    => (is => 'ro');
    has limit   => (is => 'ro');

    sub to_hash ($self) {
        return {
            type    => $self->type,
            sources => $self->sources,
            where   => $self->where ? $self->where->to_hash : undef,
            group   => $self->group,
            aggs    => [ map { $_->to_hash } $self->aggs->@* ],
            eval    => $self->eval,
            sort    => $self->sort,
            limit   => $self->limit,
        };
    }
}

# Binary expression (AND, OR)
package Sift::Query::AST::BinaryExpr {
    use v5.36;
    use Moo;
    use Types::Standard qw(Str InstanceOf);
    extends 'Sift::Query::AST::Node';
    use namespace::autoclean;

    has '+type' => (default => 'BinaryExpr');
    has op      => (is => 'ro', isa => Str, required => 1);
    has left    => (is => 'ro', isa => InstanceOf['Sift::Query::AST::Node'], required => 1);
    has right   => (is => 'ro', isa => InstanceOf['Sift::Query::AST::Node'], required => 1);

    sub to_hash ($self) {
        return {
            type  => $self->type,
            op    => $self->op,
            left  => $self->left->to_hash,
            right => $self->right->to_hash,
        };
    }
}

# Unary expression (NOT)
package Sift::Query::AST::UnaryExpr {
    use v5.36;
    use Moo;
    use Types::Standard qw(Str InstanceOf);
    extends 'Sift::Query::AST::Node';
    use namespace::autoclean;

    has '+type' => (default => 'UnaryExpr');
    has op      => (is => 'ro', isa => Str, required => 1);
    has operand => (is => 'ro', isa => InstanceOf['Sift::Query::AST::Node'], required => 1);

    sub to_hash ($self) {
        return {
            type    => $self->type,
            op      => $self->op,
            operand => $self->operand->to_hash,
        };
    }
}

# Comparison expression
package Sift::Query::AST::Comparison {
    use v5.36;
    use Moo;
    use Types::Standard qw(Str Any);
    extends 'Sift::Query::AST::Node';
    use namespace::autoclean;

    has '+type' => (default => 'Comparison');
    has field   => (is => 'ro', isa => Str, required => 1);
    has op      => (is => 'ro', isa => Str, required => 1);
    has value   => (is => 'ro', isa => Any, required => 1);

    sub to_hash ($self) {
        return {
            type  => $self->type,
            field => $self->field,
            op    => $self->op,
            value => $self->value,
        };
    }
}

# IN expression
package Sift::Query::AST::InExpr {
    use v5.36;
    use Moo;
    use Types::Standard qw(Str ArrayRef);
    extends 'Sift::Query::AST::Node';
    use namespace::autoclean;

    has '+type'  => (default => 'InExpr');
    has field    => (is => 'ro', isa => Str, required => 1);
    has values   => (is => 'ro', isa => ArrayRef, required => 1);

    sub to_hash ($self) {
        return {
            type   => $self->type,
            field  => $self->field,
            values => $self->values,
        };
    }
}

# HAS expression (field exists)
package Sift::Query::AST::HasExpr {
    use v5.36;
    use Moo;
    use Types::Standard qw(Str);
    extends 'Sift::Query::AST::Node';
    use namespace::autoclean;

    has '+type' => (default => 'HasExpr');
    has field   => (is => 'ro', isa => Str, required => 1);

    sub to_hash ($self) {
        return {
            type  => $self->type,
            field => $self->field,
        };
    }
}

# MATCHES expression (regex)
package Sift::Query::AST::MatchExpr {
    use v5.36;
    use Moo;
    use Types::Standard qw(Str);
    extends 'Sift::Query::AST::Node';
    use namespace::autoclean;

    has '+type'   => (default => 'MatchExpr');
    has field     => (is => 'ro', isa => Str, required => 1);
    has pattern   => (is => 'ro', isa => Str, required => 1);

    sub to_hash ($self) {
        return {
            type    => $self->type,
            field   => $self->field,
            pattern => $self->pattern,
        };
    }
}

# Aggregation node
package Sift::Query::AST::Aggregation {
    use v5.36;
    use Moo;
    use Types::Standard qw(Str Maybe);
    extends 'Sift::Query::AST::Node';
    use namespace::autoclean;

    has '+type' => (default => 'Aggregation');
    has func    => (is => 'ro', isa => Str, required => 1);
    has field   => (is => 'ro', isa => Maybe[Str]);

    sub to_hash ($self) {
        return {
            type  => $self->type,
            func  => $self->func,
            field => $self->field,
        };
    }
}

1;

__END__

=head1 NAME

Sift::Query::AST - Abstract Syntax Tree nodes for query language

=head1 SYNOPSIS

    use Sift::Query::AST;

    my $query = Sift::Query::AST::Query->new(
        sources => ['nginx'],
        where   => Sift::Query::AST::Comparison->new(
            field => 'status',
            op    => '>=',
            value => 500,
        ),
    );

=head1 DESCRIPTION

Defines AST node classes for the parsed query language.

=head1 NODE TYPES

=over 4

=item * Query - Top-level query

=item * BinaryExpr - AND, OR expressions

=item * UnaryExpr - NOT expression

=item * Comparison - field op value

=item * InExpr - field IN {values}

=item * HasExpr - has(field)

=item * MatchExpr - field MATCHES pattern

=item * Aggregation - count, avg, sum, min, max

=back

=cut
