package PerlText::Source::Follow;
use v5.36;
use Moo;
use Types::Standard qw(Str Int Bool CodeRef InstanceOf Maybe);
use Path::Tiny;
use IO::Select;
use namespace::autoclean;

has file => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has parser => (
    is       => 'ro',
    required => 1,
);

has poll_interval => (
    is      => 'ro',
    isa     => Int,
    default => 1,  # seconds
);

has on_event => (
    is       => 'ro',
    isa      => CodeRef,
    required => 1,
);

has on_error => (
    is      => 'ro',
    isa     => Maybe[CodeRef],
);

has _running => (
    is      => 'rw',
    isa     => Bool,
    default => 0,
);

has _fh => (
    is      => 'rw',
);

has _inode => (
    is      => 'rw',
);

sub start ($self) {
    my $path = path($self->file);

    unless ($path->exists) {
        $self->_handle_error("File not found: " . $self->file);
        return;
    }

    # Open file and seek to end
    open my $fh, '<', $path->stringify
        or do {
            $self->_handle_error("Cannot open file: $!");
            return;
        };

    seek $fh, 0, 2;  # Seek to end

    $self->_fh($fh);
    $self->_inode((stat($fh))[1]);
    $self->_running(1);

    $self->_follow_loop;
}

sub stop ($self) {
    $self->_running(0);
}

sub _follow_loop ($self) {
    my $buffer = '';

    while ($self->_running) {
        # Check if file was rotated
        $self->_check_rotation;

        my $fh = $self->_fh;
        next unless $fh;

        # Read available data
        while (my $line = <$fh>) {
            chomp $line;
            next unless $line =~ /\S/;

            my $event = $self->parser->parse_line($line, $self->file);
            if ($event) {
                $self->on_event->($event);
            }
        }

        # Clear EOF flag so we can read more
        seek $fh, 0, 1;

        # Wait before checking again
        select(undef, undef, undef, $self->poll_interval);
    }

    close $self->_fh if $self->_fh;
}

sub _check_rotation ($self) {
    my $path = path($self->file);

    return unless $path->exists;

    my $current_inode = (stat($path->stringify))[1];

    if (defined $self->_inode && $current_inode != $self->_inode) {
        # File was rotated - reopen
        close $self->_fh if $self->_fh;

        open my $fh, '<', $path->stringify
            or do {
                $self->_handle_error("Cannot reopen rotated file: $!");
                return;
            };

        $self->_fh($fh);
        $self->_inode($current_inode);
    }
}

sub _handle_error ($self, $message) {
    if ($self->on_error) {
        $self->on_error->($message);
    } else {
        warn "Follow error: $message\n";
    }
}

1;

__END__

=head1 NAME

PerlText::Source::Follow - Follow (tail -f) log files

=head1 SYNOPSIS

    use PerlText::Source::Follow;
    use PerlText::Parser::Nginx;

    my $parser = PerlText::Parser::Nginx->new;

    my $follower = PerlText::Source::Follow->new(
        file          => '/var/log/nginx/access.log',
        parser        => $parser,
        poll_interval => 1,
        on_event      => sub ($event) {
            say $event->get('ip') . ' - ' . $event->get('status');
        },
        on_error      => sub ($msg) {
            warn "Error: $msg\n";
        },
    );

    # Start following (blocks)
    $follower->start;

    # In another thread/signal handler:
    $follower->stop;

=head1 DESCRIPTION

Follows a log file like C<tail -f>, parsing new lines as they appear
and calling a callback for each event.

=head2 Features

=over 4

=item * Handles log rotation automatically

=item * Configurable poll interval

=item * Error callback for handling issues

=back

=head1 ATTRIBUTES

=head2 file

Path to the log file to follow. Required.

=head2 parser

Parser instance to parse log lines. Required.

=head2 poll_interval

Seconds between checks for new data. Default: 1.

=head2 on_event

Callback called for each parsed event. Required.
Receives a PerlText::Event object.

=head2 on_error

Optional callback for errors. Receives error message string.

=head1 METHODS

=head2 start

Start following the file. This method blocks until C<stop> is called.

=head2 stop

Stop following the file.

=cut
