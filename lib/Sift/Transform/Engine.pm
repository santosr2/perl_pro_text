package Sift::Transform::Engine;
use v5.36;
use Moo;
use Types::Standard qw(ArrayRef);
use namespace::autoclean;

has transforms => (
    is      => 'ro',
    isa     => ArrayRef,
    default => sub { [] },
);

sub add_transform ($self, $transform) {
    push $self->transforms->@*, $transform;
    return $self;
}

sub apply ($self, $events) {
    my @result = $events->@*;

    for my $transform ($self->transforms->@*) {
        @result = map { $transform->apply($_) } @result;
        @result = grep { defined } @result;
    }

    return \@result;
}

sub apply_single ($self, $event) {
    my $result = $event;

    for my $transform ($self->transforms->@*) {
        $result = $transform->apply($result);
        return undef unless defined $result;
    }

    return $result;
}

1;

__END__

=head1 NAME

Sift::Transform::Engine - Pipeline of transformations

=head1 SYNOPSIS

    use Sift::Transform::Engine;
    use Sift::Transform::Eval;

    my $engine = Sift::Transform::Engine->new;

    $engine->add_transform(
        Sift::Transform::Eval->new(code => '$status *= 1')
    );

    my $transformed = $engine->apply($events);

=head1 DESCRIPTION

Manages a pipeline of transformations to apply to log events.

=cut
