package Sift::Parser::Custom;
use v5.36;
use Moo;
use Types::Standard qw(Str RegexpRef ArrayRef HashRef Maybe);
use Sift::Event;
use namespace::autoclean;

with 'Sift::Parser::Base';

has '+source_name' => (
    default => 'custom',
);

has name => (
    is      => 'ro',
    isa     => Str,
    default => 'custom',
);

has pattern => (
    is       => 'ro',
    isa      => Str | RegexpRef,
    required => 1,
);

has _compiled_pattern => (
    is      => 'lazy',
    isa     => RegexpRef,
    builder => '_build_compiled_pattern',
);

has field_names => (
    is      => 'ro',
    isa     => ArrayRef[Str],
    lazy    => 1,
    builder => '_build_field_names',
);

has timestamp_field => (
    is      => 'ro',
    isa     => Maybe[Str],
    default => undef,
);

has timestamp_format => (
    is      => 'ro',
    isa     => Maybe[Str],
    default => undef,
);

has _timestamp_parser => (
    is      => 'lazy',
    builder => '_build_timestamp_parser',
);

has field_types => (
    is      => 'ro',
    isa     => HashRef,
    default => sub { {} },
);

sub format_name ($self) { $self->name }

sub _build_compiled_pattern ($self) {
    my $pattern = $self->pattern;

    # If already a regexp ref, return it
    return $pattern if ref $pattern eq 'Regexp';

    # Compile string pattern
    my $re = eval { qr/$pattern/ };
    die "Invalid pattern: $@" if $@;

    return $re;
}

sub _build_field_names ($self) {
    my $pattern = $self->pattern;

    # Extract named capture groups from pattern
    my @names;
    if (ref $pattern eq 'Regexp') {
        $pattern = "$pattern";  # Stringify to get pattern source
    }

    # Find all (?<name>...) patterns
    while ($pattern =~ /\(\?<(\w+)>/g) {
        push @names, $1;
    }

    return \@names;
}

sub _build_timestamp_parser ($self) {
    return undef unless $self->timestamp_format;

    require DateTime::Format::Strptime;
    return DateTime::Format::Strptime->new(
        pattern   => $self->timestamp_format,
        on_error  => 'undef',
    );
}

sub can_parse ($self, $line) {
    return 0 unless defined $line && $line =~ /\S/;
    return $line =~ $self->_compiled_pattern ? 1 : 0;
}

sub parse ($self, $line, $source = undef) {
    return undef unless defined $line && $line =~ /\S/;
    return undef unless $line =~ $self->_compiled_pattern;

    my %captured = %+;  # Named captures
    my %fields;

    # Process captured fields
    for my $name (keys %captured) {
        my $value = $captured{$name};
        next unless defined $value;

        # Apply type coercion if specified
        if (my $type = $self->field_types->{$name}) {
            $value = $self->_coerce_value($value, $type);
        }

        $fields{$name} = $value;
    }

    # Parse timestamp if configured
    my $timestamp = time();
    if ($self->timestamp_field && exists $fields{$self->timestamp_field}) {
        my $ts_str = $fields{$self->timestamp_field};
        if ($self->_timestamp_parser) {
            my $dt = $self->_timestamp_parser->parse_datetime($ts_str);
            $timestamp = $dt->epoch if $dt;
        }
        elsif ($ts_str =~ /^\d+$/) {
            $timestamp = $ts_str;
        }
    }

    return Sift::Event->new(
        timestamp => $timestamp,
        source    => $source // $self->source_name,
        raw       => $line,
        fields    => \%fields,
    );
}

sub _coerce_value ($self, $value, $type) {
    return $value unless defined $value;

    if ($type eq 'int' || $type eq 'integer') {
        return int($value) if $value =~ /^-?\d+$/;
        return 0;
    }
    elsif ($type eq 'float' || $type eq 'number') {
        return 0 + $value if $value =~ /^-?\d+(?:\.\d+)?$/;
        return 0.0;
    }
    elsif ($type eq 'bool' || $type eq 'boolean') {
        return $value && $value !~ /^(0|false|no|off)$/i ? 1 : 0;
    }
    elsif ($type eq 'lower') {
        return lc($value);
    }
    elsif ($type eq 'upper') {
        return uc($value);
    }

    return $value;
}

# Factory method to create parser from config hash
sub from_config ($class, $config) {
    return $class->new(
        name             => $config->{name}             // 'custom',
        pattern          => $config->{pattern},
        timestamp_field  => $config->{timestamp_field},
        timestamp_format => $config->{timestamp_format},
        field_types      => $config->{field_types}      // {},
        source_name      => $config->{source_name}      // 'custom',
    );
}

# Factory method to create common parsers
sub create_common ($class, $type) {
    my %common = (
        # Apache error log
        apache_error => {
            name    => 'apache_error',
            pattern => qr{
                ^\[(?<timestamp>[^\]]+)\]
                \s+\[(?:(?<module>\w+):)?(?<level>\w+)\]
                \s+\[pid\s+(?<pid>\d+)\]
                (?:\s+\[client\s+(?<client>[^\]]+)\])?
                \s+(?<message>.*)
            }x,
            timestamp_format => '%a %b %d %H:%M:%S.%6N %Y',
            field_types => {
                pid   => 'int',
                level => 'lower',
            },
        },

        # HAProxy log
        haproxy => {
            name    => 'haproxy',
            pattern => qr{
                ^(?<timestamp>\w+\s+\d+\s+[\d:]+)
                \s+(?<host>\S+)
                \s+haproxy\[(?<pid>\d+)\]:
                \s+(?<client_ip>[\d.]+):(?<client_port>\d+)
                \s+\[(?<accept_date>[^\]]+)\]
                \s+(?<frontend>\S+)
                \s+(?<backend>\S+)/(?<server>\S+)
                \s+(?<tq>\d+)/(?<tw>\d+)/(?<tc>\d+)/(?<tr>\d+)/(?<tt>\d+)
                \s+(?<status>\d+)
                \s+(?<bytes>\d+)
            }x,
            field_types => {
                pid         => 'int',
                client_port => 'int',
                tq          => 'int',
                tw          => 'int',
                tc          => 'int',
                tr          => 'int',
                tt          => 'int',
                status      => 'int',
                bytes       => 'int',
            },
        },

        # PostgreSQL log
        postgresql => {
            name    => 'postgresql',
            pattern => qr{
                ^(?<timestamp>\d{4}-\d{2}-\d{2}\s+[\d:.]+\s+\w+)
                \s+\[(?<pid>\d+)\]
                \s+(?<level>\w+):
                \s+(?<message>.*)
            }x,
            timestamp_format => '%Y-%m-%d %H:%M:%S %Z',
            field_types => {
                pid   => 'int',
                level => 'upper',
            },
        },

        # MySQL slow query log
        mysql_slow => {
            name    => 'mysql_slow',
            pattern => qr{
                ^#\s+Query_time:\s+(?<query_time>[\d.]+)
                \s+Lock_time:\s+(?<lock_time>[\d.]+)
                \s+Rows_sent:\s+(?<rows_sent>\d+)
                \s+Rows_examined:\s+(?<rows_examined>\d+)
            }x,
            field_types => {
                query_time    => 'float',
                lock_time     => 'float',
                rows_sent     => 'int',
                rows_examined => 'int',
            },
        },

        # Generic timestamp + level + message
        generic => {
            name    => 'generic',
            pattern => qr{
                ^(?<timestamp>\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)
                \s+(?<level>\w+)
                \s+(?<message>.*)
            }x,
            timestamp_field  => 'timestamp',
            timestamp_format => '%Y-%m-%dT%H:%M:%S',
            field_types => {
                level => 'lower',
            },
        },
    );

    my $config = $common{$type}
        or die "Unknown common parser type: $type\n";

    return $class->new(%$config);
}

# List available common parser types
sub list_common ($class) {
    return [qw(apache_error haproxy postgresql mysql_slow generic)];
}

1;

__END__

=head1 NAME

Sift::Parser::Custom - User-defined log parsers with regex patterns

=head1 SYNOPSIS

    use Sift::Parser::Custom;

    # Create a custom parser with named captures
    my $parser = Sift::Parser::Custom->new(
        name    => 'myapp',
        pattern => qr{
            ^(?<timestamp>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})
            \s+\[(?<level>\w+)\]
            \s+(?<message>.*)
        }x,
        timestamp_field  => 'timestamp',
        timestamp_format => '%Y-%m-%d %H:%M:%S',
        field_types      => {
            level => 'lower',
        },
    );

    my $event = $parser->parse_line($log_line);

    # Use pre-defined common parsers
    my $haproxy = Sift::Parser::Custom->create_common('haproxy');
    my $pg      = Sift::Parser::Custom->create_common('postgresql');

    # Create from config hash (useful for YAML/JSON config files)
    my $parser = Sift::Parser::Custom->from_config({
        name    => 'myformat',
        pattern => '(?<ip>\S+) - (?<message>.*)',
    });

=head1 DESCRIPTION

Allows users to define custom log parsers using Perl regular expressions
with named capture groups. Field types can be specified for automatic
type coercion.

=head1 ATTRIBUTES

=head2 name

Name for this parser format. Default: 'custom'.

=head2 pattern

Required. Regex pattern with named captures (C<(?E<lt>nameE<gt>...)>).
Can be a string or compiled qr// pattern.

=head2 timestamp_field

Name of the captured field containing the timestamp.

=head2 timestamp_format

strptime format for parsing the timestamp field.

=head2 field_types

HashRef mapping field names to types for coercion:

=over 4

=item * int/integer - Convert to integer

=item * float/number - Convert to float

=item * bool/boolean - Convert to 1/0

=item * lower - Lowercase string

=item * upper - Uppercase string

=back

=head1 CLASS METHODS

=head2 create_common($type)

Create a pre-defined common parser. Available types:

=over 4

=item * apache_error - Apache error log format

=item * haproxy - HAProxy log format

=item * postgresql - PostgreSQL log format

=item * mysql_slow - MySQL slow query log

=item * generic - Generic timestamp + level + message

=back

=head2 list_common()

Returns arrayref of available common parser type names.

=head2 from_config($hashref)

Create parser from a configuration hash (useful for YAML/JSON configs).

=cut
