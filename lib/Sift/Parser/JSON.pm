package Sift::Parser::JSON;
use v5.36;
use Moo;
use Types::Standard qw(Str);
use JSON::MaybeXS qw(decode_json);
use DateTime::Format::ISO8601;
use Sift::Event;
use namespace::autoclean;

with 'Sift::Parser::Base';

has '+source_name' => (default => 'json');

# Common timestamp field names to check
my @TIMESTAMP_FIELDS = qw(
    timestamp time @timestamp ts datetime date
    created_at createdAt logged_at loggedAt
);

sub format_name ($self) { 'json' }

sub can_parse ($self, $line) {
    return 0 unless $line =~ /^\s*\{/;
    eval { decode_json($line) };
    return $@ ? 0 : 1;
}

sub parse ($self, $line, $source = undef) {
    $source //= $self->source_name;

    my $data;
    eval { $data = decode_json($line) };
    return undef if $@ || ref $data ne 'HASH';

    my $timestamp = $self->_extract_timestamp($data);
    my %fields    = $self->_flatten_fields($data);

    return Sift::Event->new(
        timestamp => $timestamp,
        source    => $source,
        raw       => $line,
        fields    => \%fields,
    );
}

sub _extract_timestamp ($self, $data) {
    for my $field (@TIMESTAMP_FIELDS) {
        next unless exists $data->{$field};
        my $value = $data->{$field};

        # Already a number (epoch)
        return $value if $value =~ /^\d+$/;

        # Try ISO8601 format
        if ($value =~ /^\d{4}-\d{2}-\d{2}/) {
            my $dt = eval { DateTime::Format::ISO8601->parse_datetime($value) };
            return $dt->epoch if $dt;
        }
    }

    # Fallback to current time
    return time();
}

sub _flatten_fields ($self, $data, $prefix = '') {
    my %fields;

    for my $key (keys $data->%*) {
        my $full_key = $prefix ? "${prefix}.${key}" : $key;
        my $value    = $data->{$key};

        if (ref $value eq 'HASH') {
            my %nested = $self->_flatten_fields($value, $full_key);
            %fields = (%fields, %nested);
        }
        elsif (ref $value eq 'ARRAY') {
            $fields{$full_key} = $value;
        }
        else {
            $fields{$full_key} = $value;
        }
    }

    return %fields;
}

1;

__END__

=head1 NAME

Sift::Parser::JSON - Parse JSON/JSONL log lines

=head1 SYNOPSIS

    use Sift::Parser::JSON;

    my $parser = Sift::Parser::JSON->new;

    my $event = $parser->parse('{"level":"info","message":"User login","user_id":123}');
    say $event->get('level');    # info
    say $event->get('user_id');  # 123

=head1 DESCRIPTION

Parses JSON Lines (JSONL) format logs, commonly used by microservices
and structured logging frameworks.

=head1 FEATURES

=over 4

=item * Auto-detects timestamp from common field names

=item * Flattens nested objects (e.g., C<request.method>)

=item * Preserves arrays as-is

=back

=head1 TIMESTAMP DETECTION

Looks for timestamp in these fields (in order):
timestamp, time, @timestamp, ts, datetime, date,
created_at, createdAt, logged_at, loggedAt

Supports:

=over 4

=item * Unix epoch (integer)

=item * ISO8601 format (2025-12-04T10:00:00Z)

=back

=cut
