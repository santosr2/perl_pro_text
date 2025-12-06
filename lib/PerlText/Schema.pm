package PerlText::Schema;
use v5.36;
use Moo;
use Types::Standard qw(Str HashRef ArrayRef Bool);
use namespace::autoclean;

# Schema defines the expected structure of events from different log formats

has name => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has fields => (
    is      => 'ro',
    isa     => HashRef,
    default => sub { {} },
);

has required_fields => (
    is      => 'ro',
    isa     => ArrayRef[Str],
    default => sub { [] },
);

has description => (
    is      => 'ro',
    isa     => Str,
    default => '',
);

# Field type definitions
our %FIELD_TYPES = (
    string    => { coerce => sub { defined $_[0] ? "$_[0]" : '' } },
    integer   => { coerce => sub { defined $_[0] ? int($_[0]) : 0 } },
    float     => { coerce => sub { defined $_[0] ? 0 + $_[0] : 0.0 } },
    boolean   => { coerce => sub { $_[0] ? 1 : 0 } },
    timestamp => { coerce => sub { defined $_[0] ? 0 + $_[0] : time() } },
    ip        => { coerce => sub { defined $_[0] ? "$_[0]" : '' } },
    url       => { coerce => sub { defined $_[0] ? "$_[0]" : '' } },
);

# Pre-defined schemas for common log formats
my %SCHEMAS;

sub _build_schemas {
    return if %SCHEMAS;

    %SCHEMAS = (
        nginx => __PACKAGE__->new(
            name        => 'nginx',
            description => 'Nginx access log schema',
            required_fields => [qw(ip method path status)],
            fields      => {
                ip         => { type => 'ip',        description => 'Client IP address' },
                user       => { type => 'string',    description => 'Authenticated user' },
                timestamp  => { type => 'timestamp', description => 'Request timestamp' },
                method     => { type => 'string',    description => 'HTTP method' },
                path       => { type => 'url',       description => 'Request path' },
                protocol   => { type => 'string',    description => 'HTTP protocol version' },
                status     => { type => 'integer',   description => 'HTTP status code' },
                bytes      => { type => 'integer',   description => 'Response size in bytes' },
                referer    => { type => 'url',       description => 'Referer URL' },
                user_agent => { type => 'string',    description => 'User agent string' },
            },
        ),

        apache => __PACKAGE__->new(
            name        => 'apache',
            description => 'Apache access log schema',
            required_fields => [qw(ip method path status)],
            fields      => {
                ip         => { type => 'ip',        description => 'Client IP address' },
                ident      => { type => 'string',    description => 'Remote logname' },
                user       => { type => 'string',    description => 'Authenticated user' },
                timestamp  => { type => 'timestamp', description => 'Request timestamp' },
                method     => { type => 'string',    description => 'HTTP method' },
                path       => { type => 'url',       description => 'Request path' },
                protocol   => { type => 'string',    description => 'HTTP protocol version' },
                status     => { type => 'integer',   description => 'HTTP status code' },
                bytes      => { type => 'integer',   description => 'Response size in bytes' },
                referer    => { type => 'url',       description => 'Referer URL' },
                user_agent => { type => 'string',    description => 'User agent string' },
            },
        ),

        json => __PACKAGE__->new(
            name        => 'json',
            description => 'Generic JSON log schema',
            required_fields => [],
            fields      => {
                # JSON logs can have any fields
                level     => { type => 'string',    description => 'Log level' },
                message   => { type => 'string',    description => 'Log message' },
                timestamp => { type => 'timestamp', description => 'Event timestamp' },
            },
        ),

        syslog => __PACKAGE__->new(
            name        => 'syslog',
            description => 'Syslog format schema',
            required_fields => [qw(host program message)],
            fields      => {
                timestamp => { type => 'timestamp', description => 'Event timestamp' },
                host      => { type => 'string',    description => 'Hostname' },
                program   => { type => 'string',    description => 'Program name' },
                pid       => { type => 'integer',   description => 'Process ID' },
                message   => { type => 'string',    description => 'Log message' },
                facility  => { type => 'string',    description => 'Syslog facility' },
                severity  => { type => 'string',    description => 'Syslog severity' },
                priority  => { type => 'integer',   description => 'Syslog priority' },
            },
        ),

        kubernetes => __PACKAGE__->new(
            name        => 'kubernetes',
            description => 'Kubernetes pod log schema',
            required_fields => [qw(message)],
            fields      => {
                timestamp => { type => 'timestamp', description => 'Log timestamp' },
                namespace => { type => 'string',    description => 'Kubernetes namespace' },
                pod       => { type => 'string',    description => 'Pod name' },
                container => { type => 'string',    description => 'Container name' },
                level     => { type => 'string',    description => 'Log level' },
                message   => { type => 'string',    description => 'Log message' },
            },
        ),

        cloudwatch => __PACKAGE__->new(
            name        => 'cloudwatch',
            description => 'AWS CloudWatch Logs schema',
            required_fields => [qw(message)],
            fields      => {
                timestamp     => { type => 'timestamp', description => 'Event timestamp' },
                log_group     => { type => 'string',    description => 'Log group name' },
                log_stream    => { type => 'string',    description => 'Log stream name' },
                message       => { type => 'string',    description => 'Log message' },
                ingestion_time => { type => 'timestamp', description => 'Ingestion timestamp' },
            },
        ),
    );
}

# Get a pre-defined schema by name
sub get ($class, $name) {
    _build_schemas();
    return $SCHEMAS{$name};
}

# List all available schema names
sub available ($class) {
    _build_schemas();
    return [ sort keys %SCHEMAS ];
}

# Register a custom schema
sub register ($class, $schema) {
    _build_schemas();
    $SCHEMAS{$schema->name} = $schema;
    return $schema;
}

# Validate an event against this schema
sub validate ($self, $event) {
    my @errors;

    # Check required fields
    for my $field ($self->required_fields->@*) {
        unless (defined $event->get($field)) {
            push @errors, "Missing required field: $field";
        }
    }

    return @errors ? \@errors : undef;
}

# Coerce event fields to expected types
sub coerce ($self, $event) {
    my $fields = { $event->fields->%* };

    for my $name (keys $self->fields->%*) {
        next unless exists $fields->{$name};

        my $field_def = $self->fields->{$name};
        my $type = $field_def->{type} // 'string';

        if (my $type_def = $FIELD_TYPES{$type}) {
            $fields->{$name} = $type_def->{coerce}->($fields->{$name});
        }
    }

    return ref($event)->new(
        timestamp => $event->timestamp,
        source    => $event->source,
        raw       => $event->raw,
        fields    => $fields,
    );
}

# Get field info
sub field_info ($self, $field_name) {
    return $self->fields->{$field_name};
}

# Get all field names
sub field_names ($self) {
    return [ sort keys $self->fields->%* ];
}

1;

__END__

=head1 NAME

PerlText::Schema - Unified event schema definitions

=head1 SYNOPSIS

    use PerlText::Schema;

    # Get a pre-defined schema
    my $schema = PerlText::Schema->get('nginx');

    # Validate an event
    my $errors = $schema->validate($event);
    if ($errors) {
        warn "Validation errors: @$errors";
    }

    # Coerce field types
    my $coerced = $schema->coerce($event);

    # List available schemas
    my $names = PerlText::Schema->available;

    # Register a custom schema
    my $custom = PerlText::Schema->new(
        name   => 'myapp',
        fields => {
            request_id => { type => 'string', description => 'Unique request ID' },
            duration   => { type => 'float',  description => 'Request duration' },
        },
        required_fields => ['request_id'],
    );
    PerlText::Schema->register($custom);

=head1 DESCRIPTION

Defines and manages schemas for different log formats. Schemas specify
expected fields, their types, and validation rules.

=head1 PRE-DEFINED SCHEMAS

=over 4

=item * nginx - Nginx access log

=item * apache - Apache access log

=item * json - Generic JSON logs

=item * syslog - Syslog format

=item * kubernetes - Kubernetes pod logs

=item * cloudwatch - AWS CloudWatch Logs

=back

=head1 FIELD TYPES

=over 4

=item * string - Text values

=item * integer - Whole numbers

=item * float - Decimal numbers

=item * boolean - True/false values

=item * timestamp - Unix epoch timestamps

=item * ip - IP addresses

=item * url - URL strings

=back

=cut
