package PerlText::Parser::Nginx;
use v5.36;
use Moo;
use Types::Standard qw(Str);
use DateTime::Format::Strptime;
use PerlText::Event;
use namespace::autoclean;

with 'PerlText::Parser::Base';

has '+source_name' => (default => 'nginx');

# Combined log format regex
# 192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /api/users HTTP/1.1" 200 1234 "http://example.com" "Mozilla/5.0"
my $COMBINED_RE = qr{
    ^
    (?<ip>\S+)                                    # Client IP
    \s+
    (?<ident>\S+)                                 # Ident (usually -)
    \s+
    (?<user>\S+)                                  # Remote user (usually -)
    \s+
    \[(?<time>[^\]]+)\]                           # Timestamp
    \s+
    "(?<method>\w+)\s+(?<path>\S+)\s+HTTP/[\d.]+" # Request line
    \s+
    (?<status>\d+)                                # Status code
    \s+
    (?<bytes>\d+|-)                               # Bytes sent
    (?:
        \s+
        "(?<referer>[^"]*)"                       # Referer (optional)
        \s+
        "(?<ua>[^"]*)"                            # User-Agent (optional)
    )?
    \s*$
}x;

# Error log format regex
# 2025/12/04 10:00:00 [error] 1234#5678: *90 message, client: 192.168.1.1, ...
my $ERROR_RE = qr{
    ^
    (?<time>\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2})  # Timestamp
    \s+
    \[(?<level>\w+)\]                               # Log level
    \s+
    (?<pid>\d+)\#(?<tid>\d+):                       # PID#TID
    \s+
    (?:\*(?<conn>\d+)\s+)?                          # Connection ID (optional)
    (?<message>.+)                                  # Message
    $
}x;

my $TIME_PARSER = DateTime::Format::Strptime->new(
    pattern   => '%d/%b/%Y:%H:%M:%S %z',
    locale    => 'en_US',
    on_error  => 'undef',
);

my $ERROR_TIME_PARSER = DateTime::Format::Strptime->new(
    pattern   => '%Y/%m/%d %H:%M:%S',
    on_error  => 'undef',
);

sub format_name ($self) { 'nginx' }

sub can_parse ($self, $line) {
    return 1 if $line =~ $COMBINED_RE;
    return 1 if $line =~ $ERROR_RE;
    return 0;
}

sub parse ($self, $line, $source = undef) {
    $source //= $self->source_name;

    if ($line =~ $COMBINED_RE) {
        return $self->_parse_combined(\%+, $line, $source);
    }
    elsif ($line =~ $ERROR_RE) {
        return $self->_parse_error(\%+, $line, $source);
    }

    return undef;
}

sub _parse_combined ($self, $match, $line, $source) {
    my $dt = $TIME_PARSER->parse_datetime($match->{time});
    my $timestamp = $dt ? $dt->epoch : time();

    my $bytes = $match->{bytes};
    $bytes = 0 if $bytes eq '-';

    return PerlText::Event->new(
        timestamp => $timestamp,
        source    => $source,
        raw       => $line,
        fields    => {
            ip      => $match->{ip},
            ident   => $match->{ident},
            user    => $match->{user},
            method  => $match->{method},
            path    => $match->{path},
            status  => 0 + $match->{status},
            bytes   => 0 + $bytes,
            referer => $match->{referer} // '',
            ua      => $match->{ua} // '',
            format  => 'combined',
        },
    );
}

sub _parse_error ($self, $match, $line, $source) {
    my $dt = $ERROR_TIME_PARSER->parse_datetime($match->{time});
    my $timestamp = $dt ? $dt->epoch : time();

    my %fields = (
        level   => $match->{level},
        pid     => 0 + $match->{pid},
        tid     => 0 + $match->{tid},
        message => $match->{message},
        format  => 'error',
    );

    $fields{conn} = 0 + $match->{conn} if defined $match->{conn};

    # Extract client IP from error message if present
    if ($match->{message} =~ /client:\s*(\S+),/) {
        $fields{client_ip} = $1;
    }

    return PerlText::Event->new(
        timestamp => $timestamp,
        source    => $source,
        raw       => $line,
        fields    => \%fields,
    );
}

1;

__END__

=head1 NAME

PerlText::Parser::Nginx - Parse Nginx access and error logs

=head1 SYNOPSIS

    use PerlText::Parser::Nginx;

    my $parser = PerlText::Parser::Nginx->new;

    my $event = $parser->parse($log_line);
    say $event->get('status');   # 200
    say $event->get('method');   # GET
    say $event->get('path');     # /api/users

=head1 DESCRIPTION

Parses Nginx combined access log format and error log format into
PerlText::Event objects.

=head1 SUPPORTED FORMATS

=head2 Combined Access Log

    192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /api HTTP/1.1" 200 1234 "http://ref" "UA"

Extracted fields: ip, ident, user, method, path, status, bytes, referer, ua

=head2 Error Log

    2025/12/04 10:00:00 [error] 1234#5678: *90 message text

Extracted fields: level, pid, tid, conn (optional), message, client_ip (if in message)

=cut
