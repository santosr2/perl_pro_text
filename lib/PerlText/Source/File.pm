package PerlText::Source::File;
use v5.36;
use Moo;
use Types::Standard qw(Str ArrayRef);
use Path::Tiny;
use PerlText::Parser::Detector;
use namespace::autoclean;

with 'PerlText::Source::Base';

has path => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has paths => (
    is      => 'lazy',
    isa     => ArrayRef[Str],
    builder => '_build_paths',
);

has detector => (
    is      => 'lazy',
    default => sub { PerlText::Parser::Detector->new },
);

has _parser => (
    is        => 'rw',
    predicate => '_has_parser',
);

sub source_type ($self) { 'file' }

sub _build_paths ($self) {
    my $pattern = $self->path;

    # Handle glob patterns
    if ($pattern =~ /[*?]/) {
        my @files = glob($pattern);
        return \@files;
    }

    return [$pattern];
}

sub fetch_events ($self, %opts) {
    my @events;
    my $limit = $opts{limit};

    for my $file_path ($self->paths->@*) {
        my $path = path($file_path);
        next unless $path->exists;

        my @lines = $path->lines_utf8({ chomp => 1 });

        # Detect format from first non-empty lines
        my @sample = grep { /\S/ } @lines[0 .. min(9, $#lines)];
        my $parser = $self->detector->detect(\@sample);
        next unless $parser;

        for my $line (@lines) {
            next unless $line =~ /\S/;

            my $event = $parser->parse($line, $file_path);
            if ($event) {
                push @events, $event;
                last if $limit && @events >= $limit;
            }
        }

        last if $limit && @events >= $limit;
    }

    return \@events;
}

sub min ($a, $b) { $a < $b ? $a : $b }

1;

__END__

=head1 NAME

PerlText::Source::File - Read log events from local files

=head1 SYNOPSIS

    use PerlText::Source::File;

    # Single file
    my $source = PerlText::Source::File->new(path => '/var/log/nginx/access.log');

    # Glob pattern
    my $source = PerlText::Source::File->new(path => '/var/log/nginx/*.log');

    my $events = $source->fetch_events(limit => 100);

=head1 DESCRIPTION

Reads log files from the local filesystem. Supports glob patterns for
matching multiple files. Auto-detects log format using PerlText::Parser::Detector.

=head1 ATTRIBUTES

=head2 path

Path to log file or glob pattern.

=head1 METHODS

=head2 fetch_events(%opts)

Fetch events from the file(s). Options:

=over 4

=item * limit - Maximum number of events to return

=back

=cut
