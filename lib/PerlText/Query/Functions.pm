package PerlText::Query::Functions;
use v5.36;
use Exporter 'import';
use Scalar::Util qw(looks_like_number);
use List::Util qw(sum min max);
use POSIX qw(floor ceil);

our @EXPORT_OK = qw(
    register_function
    get_function
    list_functions
    call_function
);

# Built-in function registry
my %FUNCTIONS;

# Register a new function
sub register_function ($name, $code, $description = '') {
    $FUNCTIONS{lc $name} = {
        code        => $code,
        description => $description,
    };
}

# Get a function by name
sub get_function ($name) {
    return $FUNCTIONS{lc $name};
}

# List all available functions
sub list_functions () {
    return { map { $_ => $FUNCTIONS{$_}{description} } keys %FUNCTIONS };
}

# Call a function by name with arguments
sub call_function ($name, @args) {
    my $func = get_function($name);
    return undef unless $func;
    return $func->{code}->(@args);
}

# ============================================================
# String Functions
# ============================================================

register_function('len', sub ($str) {
    return 0 unless defined $str;
    return length($str);
}, 'Returns the length of a string');

register_function('lower', sub ($str) {
    return '' unless defined $str;
    return lc($str);
}, 'Converts string to lowercase');

register_function('upper', sub ($str) {
    return '' unless defined $str;
    return uc($str);
}, 'Converts string to uppercase');

register_function('trim', sub ($str) {
    return '' unless defined $str;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}, 'Removes leading and trailing whitespace');

register_function('ltrim', sub ($str) {
    return '' unless defined $str;
    $str =~ s/^\s+//;
    return $str;
}, 'Removes leading whitespace');

register_function('rtrim', sub ($str) {
    return '' unless defined $str;
    $str =~ s/\s+$//;
    return $str;
}, 'Removes trailing whitespace');

register_function('substr', sub ($str, $start, $length = undef) {
    return '' unless defined $str;
    $start //= 0;
    return defined $length
        ? substr($str, $start, $length)
        : substr($str, $start);
}, 'Extracts a substring');

register_function('replace', sub ($str, $search, $replace) {
    return '' unless defined $str;
    $search  //= '';
    $replace //= '';
    $str =~ s/\Q$search\E/$replace/g;
    return $str;
}, 'Replaces all occurrences of a string');

register_function('split', sub ($str, $delimiter = ',') {
    return [] unless defined $str;
    return [ split /\Q$delimiter\E/, $str ];
}, 'Splits string into array');

register_function('join', sub ($arr, $delimiter = ',') {
    return '' unless ref $arr eq 'ARRAY';
    return join($delimiter, @$arr);
}, 'Joins array into string');

register_function('concat', sub (@parts) {
    return join('', map { $_ // '' } @parts);
}, 'Concatenates strings');

register_function('contains', sub ($str, $search) {
    return 0 unless defined $str && defined $search;
    return index($str, $search) >= 0 ? 1 : 0;
}, 'Returns 1 if string contains substring');

register_function('starts_with', sub ($str, $prefix) {
    return 0 unless defined $str && defined $prefix;
    return index($str, $prefix) == 0 ? 1 : 0;
}, 'Returns 1 if string starts with prefix');

register_function('ends_with', sub ($str, $suffix) {
    return 0 unless defined $str && defined $suffix;
    return substr($str, -length($suffix)) eq $suffix ? 1 : 0;
}, 'Returns 1 if string ends with suffix');

register_function('regex_match', sub ($str, $pattern) {
    return 0 unless defined $str && defined $pattern;
    my $re = eval { qr/$pattern/ };
    return 0 if $@;
    return $str =~ $re ? 1 : 0;
}, 'Returns 1 if string matches regex');

register_function('regex_extract', sub ($str, $pattern, $group = 0) {
    return '' unless defined $str && defined $pattern;
    my $re = eval { qr/$pattern/ };
    return '' if $@;
    my @matches = $str =~ $re;
    return @matches ? ($matches[$group] // '') : '';
}, 'Extracts regex capture group');

# ============================================================
# Numeric Functions
# ============================================================

register_function('abs', sub ($num) {
    return 0 unless looks_like_number($num);
    return abs($num);
}, 'Returns absolute value');

register_function('round', sub ($num, $precision = 0) {
    return 0 unless looks_like_number($num);
    my $factor = 10 ** $precision;
    return floor($num * $factor + 0.5) / $factor;
}, 'Rounds to specified precision');

register_function('floor', sub ($num) {
    return 0 unless looks_like_number($num);
    return floor($num);
}, 'Rounds down to nearest integer');

register_function('ceil', sub ($num) {
    return 0 unless looks_like_number($num);
    return ceil($num);
}, 'Rounds up to nearest integer');

register_function('min', sub (@nums) {
    my @valid = grep { looks_like_number($_) } @nums;
    return undef unless @valid;
    return min(@valid);
}, 'Returns minimum value');

register_function('max', sub (@nums) {
    my @valid = grep { looks_like_number($_) } @nums;
    return undef unless @valid;
    return max(@valid);
}, 'Returns maximum value');

register_function('clamp', sub ($num, $min_val, $max_val) {
    return $min_val unless looks_like_number($num);
    return $min_val if $num < $min_val;
    return $max_val if $num > $max_val;
    return $num;
}, 'Clamps value between min and max');

# ============================================================
# Date/Time Functions
# ============================================================

register_function('now', sub () {
    return time();
}, 'Returns current Unix timestamp');

register_function('timestamp', sub ($str) {
    require PerlText::Utils;
    return PerlText::Utils::parse_timestamp($str);
}, 'Parses timestamp string to epoch');

register_function('format_time', sub ($epoch, $format = '%Y-%m-%d %H:%M:%S') {
    require PerlText::Utils;
    return PerlText::Utils::format_timestamp($epoch, $format);
}, 'Formats epoch to string');

register_function('duration', sub ($str) {
    require PerlText::Utils;
    return PerlText::Utils::parse_duration($str);
}, 'Parses duration string to seconds');

register_function('ago', sub ($seconds) {
    return time() - ($seconds // 0);
}, 'Returns timestamp from N seconds ago');

# ============================================================
# Type Conversion Functions
# ============================================================

register_function('int', sub ($val) {
    return 0 unless defined $val;
    return looks_like_number($val) ? int($val) : 0;
}, 'Converts to integer');

register_function('float', sub ($val) {
    return 0.0 unless defined $val;
    return looks_like_number($val) ? 0 + $val : 0.0;
}, 'Converts to float');

register_function('string', sub ($val) {
    return '' unless defined $val;
    return "$val";
}, 'Converts to string');

register_function('bool', sub ($val) {
    return $val ? 1 : 0;
}, 'Converts to boolean (1 or 0)');

# ============================================================
# Conditional Functions
# ============================================================

register_function('if', sub ($condition, $then_val, $else_val = undef) {
    return $condition ? $then_val : $else_val;
}, 'Returns then_val if condition is true, else else_val');

register_function('coalesce', sub (@vals) {
    for my $val (@vals) {
        return $val if defined $val && $val ne '';
    }
    return undef;
}, 'Returns first non-null, non-empty value');

register_function('nullif', sub ($val1, $val2) {
    return undef if defined $val1 && defined $val2 && $val1 eq $val2;
    return $val1;
}, 'Returns null if values are equal');

register_function('default', sub ($val, $default) {
    return (defined $val && $val ne '') ? $val : $default;
}, 'Returns default if value is null or empty');

# ============================================================
# IP Address Functions
# ============================================================

register_function('is_ip', sub ($str) {
    require PerlText::Utils;
    return PerlText::Utils::is_ipv4($str) || PerlText::Utils::is_ipv6($str) ? 1 : 0;
}, 'Returns 1 if valid IP address');

register_function('is_private_ip', sub ($ip) {
    return 0 unless defined $ip;
    return 1 if $ip =~ /^10\./;
    return 1 if $ip =~ /^172\.(1[6-9]|2[0-9]|3[01])\./;
    return 1 if $ip =~ /^192\.168\./;
    return 1 if $ip =~ /^127\./;
    return 0;
}, 'Returns 1 if private/local IP');

register_function('ip_subnet', sub ($ip, $mask = 24) {
    return '' unless defined $ip && $ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
    my @octets = ($1, $2, $3, $4);
    my $bits = 32 - $mask;
    my $ip_int = ($octets[0] << 24) | ($octets[1] << 16) | ($octets[2] << 8) | $octets[3];
    my $subnet_int = ($ip_int >> $bits) << $bits;
    return join('.', ($subnet_int >> 24) & 255, ($subnet_int >> 16) & 255,
                     ($subnet_int >> 8) & 255, $subnet_int & 255) . "/$mask";
}, 'Returns subnet for IP address');

# ============================================================
# URL Functions
# ============================================================

register_function('domain', sub ($url) {
    require PerlText::Utils;
    return PerlText::Utils::extract_domain($url);
}, 'Extracts domain from URL');

register_function('path', sub ($url) {
    return '' unless defined $url;
    if ($url =~ m{^(?:https?://[^/]+)?(/[^?#]*)}) {
        return $1;
    }
    return $url =~ m{^/} ? $url : '';
}, 'Extracts path from URL');

register_function('query_param', sub ($url, $param) {
    return '' unless defined $url && defined $param;
    if ($url =~ /[?&]\Q$param\E=([^&#]*)/) {
        return $1;
    }
    return '';
}, 'Extracts query parameter from URL');

# ============================================================
# Hash/Object Functions
# ============================================================

register_function('keys', sub ($hash) {
    return [] unless ref $hash eq 'HASH';
    return [ sort keys %$hash ];
}, 'Returns array of hash keys');

register_function('values', sub ($hash) {
    return [] unless ref $hash eq 'HASH';
    return [ values %$hash ];
}, 'Returns array of hash values');

register_function('has_key', sub ($hash, $key) {
    return 0 unless ref $hash eq 'HASH' && defined $key;
    return exists $hash->{$key} ? 1 : 0;
}, 'Returns 1 if hash has key');

register_function('get', sub ($hash, $key, $default = undef) {
    return $default unless ref $hash eq 'HASH' && defined $key;
    return $hash->{$key} // $default;
}, 'Gets value from hash with default');

1;

__END__

=head1 NAME

PerlText::Query::Functions - Built-in query functions

=head1 SYNOPSIS

    use PerlText::Query::Functions qw(call_function list_functions);

    # Call a function
    my $result = call_function('upper', 'hello');  # 'HELLO'

    # List all functions
    my $funcs = list_functions();

    # Register custom function
    register_function('double', sub ($n) { $n * 2 }, 'Doubles a number');

=head1 DESCRIPTION

Provides built-in functions for use in PerlText query expressions.

=head1 FUNCTION CATEGORIES

=head2 String Functions

=over 4

=item * len(str) - String length

=item * lower(str) - Lowercase

=item * upper(str) - Uppercase

=item * trim(str) - Remove whitespace

=item * substr(str, start, len?) - Substring

=item * replace(str, search, replace) - Replace all

=item * contains(str, search) - Contains check

=item * starts_with(str, prefix) - Prefix check

=item * ends_with(str, suffix) - Suffix check

=item * regex_match(str, pattern) - Regex match

=item * regex_extract(str, pattern, group?) - Regex capture

=back

=head2 Numeric Functions

=over 4

=item * abs(num) - Absolute value

=item * round(num, precision?) - Round

=item * floor(num) - Round down

=item * ceil(num) - Round up

=item * min(nums...) - Minimum

=item * max(nums...) - Maximum

=item * clamp(num, min, max) - Clamp value

=back

=head2 Date/Time Functions

=over 4

=item * now() - Current timestamp

=item * timestamp(str) - Parse timestamp

=item * format_time(epoch, format?) - Format timestamp

=item * duration(str) - Parse duration

=item * ago(seconds) - Timestamp N seconds ago

=back

=head2 Type Conversion

=over 4

=item * int(val) - To integer

=item * float(val) - To float

=item * string(val) - To string

=item * bool(val) - To boolean

=back

=head2 Conditional Functions

=over 4

=item * if(cond, then, else?) - Conditional

=item * coalesce(vals...) - First non-null

=item * nullif(val1, val2) - Null if equal

=item * default(val, default) - Default value

=back

=head2 IP/URL Functions

=over 4

=item * is_ip(str) - Valid IP check

=item * is_private_ip(ip) - Private IP check

=item * ip_subnet(ip, mask?) - Get subnet

=item * domain(url) - Extract domain

=item * path(url) - Extract path

=item * query_param(url, param) - Extract query param

=back

=cut
