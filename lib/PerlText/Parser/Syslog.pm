package PerlText::Parser::Syslog;
use v5.36;
use Moo;
use Types::Standard qw(Str);
use DateTime::Format::Strptime;
use PerlText::Event;
use namespace::autoclean;

with 'PerlText::Parser::Base';

has '+source_name' => (default => 'syslog');

# BSD syslog format (traditional)
# Dec  4 10:00:00 hostname programname[pid]: message
my $BSD_RE = qr{
    ^
    (?<month>\w{3})                        # Month
    \s+
    (?<day>\d{1,2})                        # Day
    \s+
    (?<time>\d{2}:\d{2}:\d{2})             # Time
    \s+
    (?<hostname>\S+)                       # Hostname
    \s+
    (?<program>[^\[:]+)                    # Program name
    (?:\[(?<pid>\d+)\])?                   # PID (optional)
    :\s*
    (?<message>.*)                         # Message
    $
}x;

# RFC 5424 syslog format
# <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID STRUCTURED-DATA MSG
my $RFC5424_RE = qr{
    ^
    <(?<pri>\d+)>                          # Priority
    (?<version>\d+)?                       # Version (optional)
    \s*
    (?<timestamp>\S+)                      # Timestamp (ISO8601)
    \s+
    (?<hostname>\S+)                       # Hostname
    \s+
    (?<appname>\S+)                        # App name
    \s+
    (?<procid>\S+)                         # Process ID
    \s+
    (?<msgid>\S+)                          # Message ID
    \s+
    (?<sd>-|\[.+?\])                       # Structured data
    \s*
    (?<message>.*)                         # Message
    $
}x;

my %MONTHS = (
    Jan => 1,  Feb => 2,  Mar => 3,  Apr => 4,
    May => 5,  Jun => 6,  Jul => 7,  Aug => 8,
    Sep => 9,  Oct => 10, Nov => 11, Dec => 12,
);

my %FACILITIES = (
    0  => 'kern',     1  => 'user',     2  => 'mail',
    3  => 'daemon',   4  => 'auth',     5  => 'syslog',
    6  => 'lpr',      7  => 'news',     8  => 'uucp',
    9  => 'cron',     10 => 'authpriv', 11 => 'ftp',
    16 => 'local0',   17 => 'local1',   18 => 'local2',
    19 => 'local3',   20 => 'local4',   21 => 'local5',
    22 => 'local6',   23 => 'local7',
);

my @SEVERITIES = qw(emerg alert crit err warning notice info debug);

sub format_name ($self) { 'syslog' }

sub can_parse ($self, $line) {
    return 1 if $line =~ $BSD_RE;
    return 1 if $line =~ $RFC5424_RE;
    return 0;
}

sub parse ($self, $line, $source = undef) {
    $source //= $self->source_name;

    if ($line =~ $RFC5424_RE) {
        return $self->_parse_rfc5424(\%+, $line, $source);
    }
    elsif ($line =~ $BSD_RE) {
        return $self->_parse_bsd(\%+, $line, $source);
    }

    return undef;
}

sub _parse_bsd ($self, $match, $line, $source) {
    my $month = $MONTHS{$match->{month}} // 1;
    my $year  = (localtime)[5] + 1900;

    my ($hour, $min, $sec) = split /:/, $match->{time};

    my $timestamp = eval {
        require Time::Local;
        Time::Local::timelocal($sec, $min, $hour, $match->{day}, $month - 1, $year);
    } // time();

    my %fields = (
        hostname => $match->{hostname},
        program  => $match->{program},
        message  => $match->{message},
        format   => 'bsd',
    );

    $fields{pid} = 0 + $match->{pid} if defined $match->{pid};

    return PerlText::Event->new(
        timestamp => $timestamp,
        source    => $source,
        raw       => $line,
        fields    => \%fields,
    );
}

sub _parse_rfc5424 ($self, $match, $line, $source) {
    my $timestamp = $self->_parse_iso8601($match->{timestamp});

    my $pri      = $match->{pri};
    my $facility = int($pri / 8);
    my $severity = $pri % 8;

    my %fields = (
        hostname     => $match->{hostname},
        appname      => $match->{appname},
        procid       => $match->{procid},
        msgid        => $match->{msgid},
        message      => $match->{message},
        priority     => $pri,
        facility     => $FACILITIES{$facility} // $facility,
        severity     => $SEVERITIES[$severity] // $severity,
        format       => 'rfc5424',
    );

    $fields{version} = $match->{version} if $match->{version};

    # Parse structured data if present
    if ($match->{sd} && $match->{sd} ne '-') {
        $fields{structured_data} = $match->{sd};
    }

    return PerlText::Event->new(
        timestamp => $timestamp,
        source    => $source,
        raw       => $line,
        fields    => \%fields,
    );
}

sub _parse_iso8601 ($self, $ts) {
    my $dt = eval { DateTime::Format::ISO8601->parse_datetime($ts) };
    return $dt ? $dt->epoch : time();
}

1;

__END__

=head1 NAME

PerlText::Parser::Syslog - Parse syslog format logs (BSD and RFC5424)

=head1 SYNOPSIS

    use PerlText::Parser::Syslog;

    my $parser = PerlText::Parser::Syslog->new;

    # BSD format
    my $event = $parser->parse('Dec  4 10:00:00 host sshd[1234]: Connection from 1.2.3.4');

    # RFC5424 format
    my $event = $parser->parse('<134>1 2025-12-04T10:00:00Z host app 1234 - - Message');

=head1 DESCRIPTION

Parses both BSD-style traditional syslog format and RFC5424 structured
syslog format.

=head1 BSD FORMAT

    Dec  4 10:00:00 hostname programname[pid]: message

Fields: hostname, program, pid (optional), message

=head1 RFC5424 FORMAT

    <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID SD MSG

Fields: hostname, appname, procid, msgid, message, priority, facility, severity

=cut
