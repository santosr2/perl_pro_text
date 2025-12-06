package Sift::Utils;
use v5.36;
use Exporter 'import';
use DateTime;
use DateTime::Format::ISO8601;
use DateTime::Format::Strptime;
use Scalar::Util qw(looks_like_number);

our @EXPORT_OK = qw(
    parse_duration
    parse_timestamp
    format_timestamp
    format_bytes
    format_duration
    truncate_string
    colorize
    is_ipv4
    is_ipv6
    extract_domain
    normalize_path
    safe_regex
);

our %EXPORT_TAGS = (
    all  => \@EXPORT_OK,
    time => [qw(parse_duration parse_timestamp format_timestamp format_duration)],
    fmt  => [qw(format_bytes truncate_string colorize)],
    net  => [qw(is_ipv4 is_ipv6 extract_domain)],
);

# Parse duration strings like "1h", "30m", "2d" into seconds
sub parse_duration ($str) {
    return 0 unless defined $str;

    my %units = (
        s => 1,
        m => 60,
        h => 3600,
        d => 86400,
        w => 604800,
    );

    if ($str =~ /^(\d+(?:\.\d+)?)\s*([smhdw])?$/i) {
        my $value = $1;
        my $unit  = lc($2 // 's');
        return $value * ($units{$unit} // 1);
    }

    # Try parsing as number of seconds
    return looks_like_number($str) ? $str : 0;
}

# Parse various timestamp formats into epoch seconds
sub parse_timestamp ($str) {
    return time() unless defined $str && $str =~ /\S/;

    # Already a number (epoch)
    return $str if looks_like_number($str) && $str > 1_000_000_000;

    # ISO 8601
    if ($str =~ /^\d{4}-\d{2}-\d{2}/) {
        my $dt = eval { DateTime::Format::ISO8601->parse_datetime($str) };
        return $dt->epoch if $dt;
    }

    # Common log format: [04/Dec/2025:10:15:30 +0000]
    if ($str =~ m{^\[?(\d{2}/\w{3}/\d{4}:\d{2}:\d{2}:\d{2}\s+[+-]\d{4})\]?$}) {
        my $parser = DateTime::Format::Strptime->new(
            pattern   => '%d/%b/%Y:%H:%M:%S %z',
            on_error  => 'undef',
        );
        my $dt = $parser->parse_datetime($1);
        return $dt->epoch if $dt;
    }

    # Syslog format: Dec  4 10:15:30
    if ($str =~ /^(\w{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})/) {
        my %months = (
            Jan => 1, Feb => 2, Mar => 3, Apr => 4,
            May => 5, Jun => 6, Jul => 7, Aug => 8,
            Sep => 9, Oct => 10, Nov => 11, Dec => 12,
        );
        my $dt = eval {
            DateTime->new(
                year   => (localtime)[5] + 1900,
                month  => $months{$1} // 1,
                day    => $2,
                hour   => $3,
                minute => $4,
                second => $5,
            );
        };
        return $dt->epoch if $dt;
    }

    return time();
}

# Format epoch timestamp to human-readable string
sub format_timestamp ($epoch, $format = '%Y-%m-%d %H:%M:%S') {
    return '' unless defined $epoch;

    my $dt = eval { DateTime->from_epoch(epoch => $epoch) };
    return $dt ? $dt->strftime($format) : '';
}

# Format bytes to human-readable size
sub format_bytes ($bytes) {
    return '0 B' unless defined $bytes && $bytes >= 0;

    my @units = qw(B KB MB GB TB PB);
    my $unit_index = 0;

    while ($bytes >= 1024 && $unit_index < $#units) {
        $bytes /= 1024;
        $unit_index++;
    }

    return $unit_index == 0
        ? sprintf("%d %s", $bytes, $units[$unit_index])
        : sprintf("%.1f %s", $bytes, $units[$unit_index]);
}

# Format duration in seconds to human-readable string
sub format_duration ($seconds) {
    return '0s' unless defined $seconds && $seconds >= 0;

    if ($seconds < 1) {
        return sprintf("%.0fms", $seconds * 1000);
    }
    elsif ($seconds < 60) {
        return sprintf("%.1fs", $seconds);
    }
    elsif ($seconds < 3600) {
        my $m = int($seconds / 60);
        my $s = $seconds % 60;
        return $s ? sprintf("%dm %ds", $m, $s) : sprintf("%dm", $m);
    }
    elsif ($seconds < 86400) {
        my $h = int($seconds / 3600);
        my $m = int(($seconds % 3600) / 60);
        return $m ? sprintf("%dh %dm", $h, $m) : sprintf("%dh", $h);
    }
    else {
        my $d = int($seconds / 86400);
        my $h = int(($seconds % 86400) / 3600);
        return $h ? sprintf("%dd %dh", $d, $h) : sprintf("%dd", $d);
    }
}

# Truncate string with ellipsis
sub truncate_string ($str, $max_len = 80, $ellipsis = '...') {
    return '' unless defined $str;
    return $str if length($str) <= $max_len;

    my $truncate_at = $max_len - length($ellipsis);
    return substr($str, 0, $truncate_at) . $ellipsis;
}

# Colorize text for terminal output
sub colorize ($text, $color) {
    return $text if $ENV{NO_COLOR};

    my %colors = (
        red     => "\e[31m",
        green   => "\e[32m",
        yellow  => "\e[33m",
        blue    => "\e[34m",
        magenta => "\e[35m",
        cyan    => "\e[36m",
        white   => "\e[37m",
        bold    => "\e[1m",
        reset   => "\e[0m",
    );

    my $code = $colors{lc $color} // '';
    return $code ? "${code}${text}\e[0m" : $text;
}

# Validate IPv4 address
sub is_ipv4 ($str) {
    return 0 unless defined $str;
    return $str =~ /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
}

# Validate IPv6 address (simplified check)
sub is_ipv6 ($str) {
    return 0 unless defined $str;
    return $str =~ /^(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$/ ||
           $str =~ /^::(?:[0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}$/ ||
           $str =~ /^(?:[0-9a-fA-F]{1,4}:){1,7}:$/;
}

# Extract domain from URL
sub extract_domain ($url) {
    return '' unless defined $url;

    if ($url =~ m{^(?:https?://)?([^/:]+)}) {
        return $1;
    }

    return '';
}

# Normalize URL path (remove query strings, fragments)
sub normalize_path ($path) {
    return '' unless defined $path;

    # Remove query string and fragment
    $path =~ s/[?#].*//;

    # Normalize multiple slashes
    $path =~ s{//+}{/}g;

    # Remove trailing slash (except for root)
    $path =~ s{/+$}{} unless $path eq '/';

    return $path;
}

# Safely compile a regex, returning undef on error
sub safe_regex ($pattern, $flags = '') {
    return undef unless defined $pattern;

    my $regex = eval {
        $flags ? qr/(?$flags)$pattern/ : qr/$pattern/;
    };

    return $@ ? undef : $regex;
}

1;

__END__

=head1 NAME

Sift::Utils - Shared utility functions

=head1 SYNOPSIS

    use Sift::Utils qw(:all);

    # Time utilities
    my $seconds = parse_duration('2h30m');
    my $epoch   = parse_timestamp('2025-12-04T10:00:00Z');
    my $str     = format_timestamp($epoch);
    my $dur     = format_duration(3665);  # "1h 1m"

    # Formatting
    my $size = format_bytes(1536);        # "1.5 KB"
    my $text = truncate_string($long_text, 50);
    my $colored = colorize('ERROR', 'red');

    # Network
    my $valid = is_ipv4('192.168.1.1');
    my $domain = extract_domain('https://example.com/path');

=head1 DESCRIPTION

Collection of utility functions used throughout Sift Pro.

=head1 EXPORT TAGS

=over 4

=item * C<:all> - All functions

=item * C<:time> - Time-related functions

=item * C<:fmt> - Formatting functions

=item * C<:net> - Network-related functions

=back

=head1 FUNCTIONS

=head2 parse_duration($str)

Parse duration string (e.g., "1h", "30m", "2d") into seconds.

=head2 parse_timestamp($str)

Parse various timestamp formats into Unix epoch.

=head2 format_timestamp($epoch, $format?)

Format epoch to human-readable string.

=head2 format_bytes($bytes)

Format bytes to human-readable size (KB, MB, etc.).

=head2 format_duration($seconds)

Format seconds to human-readable duration.

=head2 truncate_string($str, $max_len?, $ellipsis?)

Truncate string with ellipsis.

=head2 colorize($text, $color)

Add ANSI color codes. Respects C<NO_COLOR> environment variable.

=head2 is_ipv4($str)

Returns true if string is valid IPv4 address.

=head2 is_ipv6($str)

Returns true if string is valid IPv6 address.

=head2 extract_domain($url)

Extract domain from URL.

=head2 normalize_path($path)

Normalize URL path (remove query strings, fragments, extra slashes).

=head2 safe_regex($pattern, $flags?)

Safely compile regex, returns undef on error.

=cut
