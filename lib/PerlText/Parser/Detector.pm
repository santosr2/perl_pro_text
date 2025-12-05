package PerlText::Parser::Detector;
use v5.36;
use Moo;
use Types::Standard qw(ArrayRef InstanceOf);
use Module::Runtime qw(use_module);
use namespace::autoclean;

use PerlText::Parser::Nginx;
use PerlText::Parser::JSON;
use PerlText::Parser::Syslog;

has parsers => (
    is      => 'ro',
    isa     => ArrayRef,
    lazy    => 1,
    builder => '_build_parsers',
);

has sample_size => (
    is      => 'ro',
    default => 10,
);

sub _build_parsers ($self) {
    return [
        PerlText::Parser::Nginx->new,
        PerlText::Parser::JSON->new,
        PerlText::Parser::Syslog->new,
    ];
}

sub register_parser ($self, $parser) {
    push $self->parsers->@*, $parser;
    return $self;
}

sub detect ($self, $lines) {
    my @sample = $lines->@* > $self->sample_size
        ? $lines->@[0 .. $self->sample_size - 1]
        : $lines->@*;

    my @scored = map {
        { parser => $_, score => $_->confidence_score(\@sample) }
    } $self->parsers->@*;

    @scored = sort { $b->{score} <=> $a->{score} } @scored;

    return undef unless @scored && $scored[0]->{score} > 0;
    return $scored[0]->{parser};
}

sub detect_from_file ($self, $file_path) {
    use Path::Tiny;
    my $path  = path($file_path);
    my @lines = $path->lines({ chomp => 1, count => $self->sample_size });
    return $self->detect(\@lines);
}

sub detect_and_parse ($self, $lines) {
    my $parser = $self->detect($lines);
    return [] unless $parser;
    return $parser->parse_lines($lines);
}

sub available_formats ($self) {
    return [ map { $_->format_name } $self->parsers->@* ];
}

1;

__END__

=head1 NAME

PerlText::Parser::Detector - Auto-detect log format from sample lines

=head1 SYNOPSIS

    use PerlText::Parser::Detector;

    my $detector = PerlText::Parser::Detector->new;

    # Detect format from lines
    my $parser = $detector->detect(\@log_lines);
    say "Detected format: " . $parser->format_name;

    # Detect from file
    my $parser = $detector->detect_from_file('/var/log/nginx/access.log');

    # Detect and parse in one step
    my $events = $detector->detect_and_parse(\@lines);

=head1 DESCRIPTION

Automatically detects the log format of given sample lines by scoring
each registered parser's confidence and selecting the best match.

=head1 ATTRIBUTES

=head2 parsers

ArrayRef of parser instances to try. Defaults to built-in parsers.

=head2 sample_size

Number of lines to sample for detection. Default: 10.

=head1 METHODS

=head2 detect($lines)

Detect the best parser for the given lines. Returns parser instance or undef.

=head2 detect_from_file($path)

Read sample lines from file and detect format.

=head2 detect_and_parse($lines)

Detect format and parse all lines, returning arrayref of events.

=head2 register_parser($parser)

Add a custom parser to the detection pool.

=head2 available_formats

Return arrayref of format names from all registered parsers.

=cut
