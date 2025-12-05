package PerlText::Source::Kubernetes;
use v5.36;
use Moo;
use Types::Standard qw(Str Maybe ArrayRef);
use IPC::Run3;
use PerlText::Parser::Detector;
use namespace::autoclean;

with 'PerlText::Source::Base';

has namespace => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has pod => (
    is  => 'ro',
    isa => Maybe[Str],
);

has selector => (
    is  => 'ro',
    isa => Maybe[Str],
);

has container => (
    is  => 'ro',
    isa => Maybe[Str],
);

has since => (
    is      => 'ro',
    isa     => Str,
    default => '1h',
);

has tail => (
    is  => 'ro',
    isa => Maybe[Str],
);

has context => (
    is  => 'ro',
    isa => Maybe[Str],
);

has detector => (
    is      => 'lazy',
    default => sub { PerlText::Parser::Detector->new },
);

sub source_type ($self) { 'k8s' }

sub _build_source_name ($self) {
    my $name = 'k8s:' . $self->namespace;
    $name .= '/' . $self->pod if $self->pod;
    return $name;
}

sub fetch_events ($self, %opts) {
    my @cmd = $self->_build_command;

    my ($stdout, $stderr);
    run3 \@cmd, undef, \$stdout, \$stderr;

    if ($?) {
        my $exit_code = $? >> 8;
        die "kubectl failed (exit $exit_code): $stderr\n" if $exit_code;
    }

    my @lines = split /\n/, $stdout;
    return [] unless @lines;

    my $parser = $self->detector->detect(\@lines);
    return [] unless $parser;

    return $parser->parse_lines(\@lines, $self->source_name);
}

sub _build_command ($self) {
    my @cmd = ('kubectl', 'logs');

    push @cmd, '--context', $self->context if $self->context;
    push @cmd, '-n', $self->namespace;

    if ($self->selector) {
        push @cmd, '-l', $self->selector;
    }
    elsif ($self->pod) {
        push @cmd, $self->pod;
    }
    else {
        die "Either pod or selector is required\n";
    }

    push @cmd, '-c', $self->container if $self->container;
    push @cmd, '--since', $self->since;
    push @cmd, '--tail', $self->tail if $self->tail;
    push @cmd, '--timestamps';

    return @cmd;
}

1;

__END__

=head1 NAME

PerlText::Source::Kubernetes - Fetch logs from Kubernetes pods

=head1 SYNOPSIS

    use PerlText::Source::Kubernetes;

    my $source = PerlText::Source::Kubernetes->new(
        namespace => 'production',
        selector  => 'app=nginx',
        since     => '30m',
    );

    my $events = $source->fetch_events;

=head1 DESCRIPTION

Fetches logs from Kubernetes pods using kubectl.

=head1 ATTRIBUTES

=head2 namespace

Required. Kubernetes namespace.

=head2 pod

Pod name. Either pod or selector is required.

=head2 selector

Label selector (e.g., 'app=nginx'). Either pod or selector is required.

=head2 container

Container name within the pod.

=head2 since

Time duration (e.g., '1h', '30m'). Default: '1h'.

=head2 tail

Number of lines from end.

=head2 context

Kubernetes context name.

=cut
