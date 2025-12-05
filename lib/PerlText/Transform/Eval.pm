package PerlText::Transform::Eval;
use v5.36;
use Moo;
use Types::Standard qw(Str CodeRef);
use Safe;
use namespace::autoclean;

has code => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has _compiled => (
    is      => 'lazy',
    isa     => CodeRef,
    builder => '_build_compiled',
);

has _safe => (
    is      => 'lazy',
    builder => '_build_safe',
);

sub _build_safe ($self) {
    my $compartment = Safe->new;
    $compartment->permit_only(qw(
        :base_core
        :base_mem
        :base_loop
        :base_math
        padany
        padsv
        concat
        stringify
        uc lc ucfirst lcfirst
        substr index rindex
        split join
        sprintf
        length
        defined
        match subst
        rv2av rv2hv
        aelem helem
        aslice hslice
        keys values each
        exists delete
        push pop shift unshift
        reverse sort
        wantarray
    ));
    return $compartment;
}

sub _build_compiled ($self) {
    my $code = $self->code;

    # Wrap the code to operate on $_ (the event fields hashref)
    my $wrapped = qq{
        sub {
            my \$fields = shift;
            local *_ = \\\$fields;
            for my \$k (keys \%\$fields) {
                no strict 'refs';
                \${\$k} = \$fields->{\$k};
            }
            $code;
            for my \$k (keys \%\$fields) {
                no strict 'refs';
                \$fields->{\$k} = \${\$k};
            }
            return \$fields;
        }
    };

    my $sub = $self->_safe->reval($wrapped);
    die "Failed to compile transform: $@" if $@;

    return $sub;
}

sub apply ($self, $event) {
    return undef unless $event;

    my $fields = { $event->fields->%* };

    eval {
        $fields = $self->_compiled->($fields);
    };

    if ($@) {
        warn "Transform error: $@";
        return $event;
    }

    # Return new event with modified fields
    return ref($event)->new(
        timestamp => $event->timestamp,
        source    => $event->source,
        raw       => $event->raw,
        fields    => $fields,
    );
}

1;

__END__

=head1 NAME

PerlText::Transform::Eval - Safe Perl eval transformations

=head1 SYNOPSIS

    use PerlText::Transform::Eval;

    # Simple field modification
    my $t = PerlText::Transform::Eval->new(
        code => '$status = int($status)'
    );

    # Add computed field
    my $t = PerlText::Transform::Eval->new(
        code => '$duration_ms = $duration * 1000'
    );

    # Conditional modification
    my $t = PerlText::Transform::Eval->new(
        code => '$level = "critical" if $status >= 500'
    );

    my $new_event = $t->apply($event);

=head1 DESCRIPTION

Applies Perl expressions to transform event fields. Uses Safe.pm to
restrict available operations for security.

Field values are available as package variables matching their names:
C<$status>, C<$message>, C<$ip>, etc.

=head1 SECURITY

The eval runs in a Safe compartment with restricted operations.
Only basic operations are permitted:

=over 4

=item * Math operations

=item * String operations (uc, lc, substr, etc.)

=item * Array/hash access

=item * Basic control flow

=back

=cut
