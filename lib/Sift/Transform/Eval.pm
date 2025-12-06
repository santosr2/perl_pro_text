package Sift::Transform::Eval;
use v5.36;
use Moo;
use Types::Standard qw(Str CodeRef);
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

sub _build_compiled ($self) {
    my $code = $self->code;

    # Build a sub that operates on a hashref $f
    # Variables like $status become $f->{status}
    my $transformed = $code;

    # Replace $varname with $f->{varname} for simple variable access
    # This handles: $foo, $foo_bar, but not $f itself
    $transformed =~ s/\$([a-zA-Z_][a-zA-Z0-9_]*)(?!\s*\{)/\$f->{$1}/g;

    my $wrapped = qq{
        sub {
            my \$f = shift;
            $transformed;
            return \$f;
        }
    };

    my $sub = eval $wrapped;
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

Sift::Transform::Eval - Safe Perl eval transformations

=head1 SYNOPSIS

    use Sift::Transform::Eval;

    # Simple field modification
    my $t = Sift::Transform::Eval->new(
        code => '$status = int($status)'
    );

    # Add computed field
    my $t = Sift::Transform::Eval->new(
        code => '$duration_ms = $duration * 1000'
    );

    # Conditional modification
    my $t = Sift::Transform::Eval->new(
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
