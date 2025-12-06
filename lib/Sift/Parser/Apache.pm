package Sift::Parser::Apache;
use v5.36;
use Moo;
use DateTime::Format::Strptime;
use Sift::Event;
use namespace::autoclean;

with 'Sift::Parser::Base';

has '+source_name' => (
    default => 'apache',
);

has _timestamp_parser => (
    is      => 'lazy',
    builder => sub {
        DateTime::Format::Strptime->new(
            pattern   => '%d/%b/%Y:%H:%M:%S %z',
            on_error  => 'undef',
        );
    },
);

sub format_name ($self) { 'apache' }

# Apache Combined Log Format:
# %h %l %u %t "%r" %>s %b "%{Referer}i" "%{User-Agent}i"
# 192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /path HTTP/1.1" 200 1234 "http://referer.com" "Mozilla/5.0"
#
# Apache Common Log Format:
# %h %l %u %t "%r" %>s %b
# 192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /path HTTP/1.1" 200 1234

my $COMBINED_REGEX = qr{
    ^
    (?<ip>\S+)                          # Remote host
    \s+
    (?<ident>\S+)                       # Remote logname (usually -)
    \s+
    (?<user>\S+)                        # Remote user (usually -)
    \s+
    \[(?<timestamp>[^\]]+)\]            # Time in brackets
    \s+
    "(?<request>[^"]*)"                 # Request line in quotes
    \s+
    (?<status>\d+)                      # Status code
    \s+
    (?<bytes>\S+)                       # Response size (- for no content)
    (?:
        \s+
        "(?<referer>[^"]*)"             # Referer (optional)
        \s+
        "(?<user_agent>[^"]*)"          # User-Agent (optional)
    )?
    \s*$
}x;

my $REQUEST_REGEX = qr{^(?<method>\w+)\s+(?<path>\S+)(?:\s+(?<protocol>\S+))?$};

sub can_parse ($self, $line) {
    return 0 unless defined $line && $line =~ /\S/;
    return $line =~ $COMBINED_REGEX ? 1 : 0;
}

sub parse ($self, $line, $source = undef) {
    return undef unless $line =~ /\S/;
    return undef unless $line =~ $COMBINED_REGEX;

    my %captured = %+;
    my %fields = (
        ip     => $captured{ip},
        status => int($captured{status}),
    );

    # Parse request line
    if ($captured{request} && $captured{request} =~ $REQUEST_REGEX) {
        $fields{method}   = $+{method};
        $fields{path}     = $+{path};
        $fields{protocol} = $+{protocol} // 'HTTP/1.0';
    } else {
        $fields{request} = $captured{request};
    }

    # Handle bytes (can be -)
    if ($captured{bytes} && $captured{bytes} ne '-') {
        $fields{bytes} = int($captured{bytes});
    }

    # Optional fields from combined format
    $fields{user}       = $captured{user}       if $captured{user}       && $captured{user}       ne '-';
    $fields{ident}      = $captured{ident}      if $captured{ident}      && $captured{ident}      ne '-';
    $fields{referer}    = $captured{referer}    if $captured{referer}    && $captured{referer}    ne '-';
    $fields{user_agent} = $captured{user_agent} if defined $captured{user_agent};

    # Parse timestamp
    my $timestamp = time();
    if ($captured{timestamp}) {
        my $dt = $self->_timestamp_parser->parse_datetime($captured{timestamp});
        $timestamp = $dt->epoch if $dt;
    }

    return Sift::Event->new(
        timestamp => $timestamp,
        source    => $source // $self->source_name,
        raw       => $line,
        fields    => \%fields,
    );
}

1;

__END__

=head1 NAME

Sift::Parser::Apache - Parser for Apache access logs

=head1 SYNOPSIS

    use Sift::Parser::Apache;

    my $parser = Sift::Parser::Apache->new;
    my $event = $parser->parse_line($log_line);

    # Access fields
    say $event->get('ip');
    say $event->get('method');
    say $event->get('status');

=head1 DESCRIPTION

Parses Apache HTTP Server access logs in Common and Combined formats.

=head2 Supported Formats

=over 4

=item * Apache Common Log Format

C<%h %l %u %t "%r" %E<gt>s %b>

=item * Apache Combined Log Format

C<%h %l %u %t "%r" %E<gt>s %b "%{Referer}i" "%{User-Agent}i">

=back

=head2 Extracted Fields

=over 4

=item * ip - Client IP address

=item * method - HTTP method (GET, POST, etc.)

=item * path - Request path

=item * protocol - HTTP protocol version

=item * status - HTTP status code

=item * bytes - Response size in bytes

=item * referer - Referer URL (combined format only)

=item * user_agent - User agent string (combined format only)

=item * user - Authenticated user (if present)

=back

=cut
