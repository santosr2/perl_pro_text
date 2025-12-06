package Sift::Config;
use v5.36;
use Moo;
use Types::Standard qw(Str HashRef Maybe);
use Path::Tiny;
use YAML::XS ();
use namespace::autoclean;

has config_file => (
    is      => 'ro',
    isa     => Maybe[Str],
    lazy    => 1,
    builder => '_build_config_file',
);

has _config => (
    is      => 'lazy',
    isa     => HashRef,
    builder => '_build_config',
);

sub _build_config_file ($self) {
    # Check environment variable first
    return $ENV{PTX_CONFIG} if $ENV{PTX_CONFIG} && -f $ENV{PTX_CONFIG};

    # Check common locations
    my @locations = (
        path('.ptxrc'),
        path('.ptx.yml'),
        path('.ptx.yaml'),
        path($ENV{HOME}, '.ptxrc'),
        path($ENV{HOME}, '.config/ptx/config.yml'),
        path('/etc/ptx/config.yml'),
    );

    for my $loc (@locations) {
        return $loc->stringify if $loc->exists;
    }

    return undef;
}

sub _build_config ($self) {
    return {} unless $self->config_file && -f $self->config_file;

    my $content = path($self->config_file)->slurp_utf8;
    my $config = eval { YAML::XS::Load($content) } // {};

    return $config;
}

# Get a configuration value with optional default
sub get ($self, $key, $default = undef) {
    my @parts = split /\./, $key;
    my $value = $self->_config;

    for my $part (@parts) {
        return $default unless ref $value eq 'HASH';
        return $default unless exists $value->{$part};
        $value = $value->{$part};
    }

    return $value // $default;
}

# Get default output format
sub default_output ($self) {
    return $self->get('defaults.output', 'table');
}

# Get default limit
sub default_limit ($self) {
    return $self->get('defaults.limit');
}

# Get AWS configuration
sub aws_profile ($self) {
    return $self->get('aws.profile', $ENV{AWS_PROFILE});
}

sub aws_region ($self) {
    return $self->get('aws.region', $ENV{AWS_DEFAULT_REGION});
}

# Get GCP configuration
sub gcp_project ($self) {
    return $self->get('gcp.project', $ENV{GOOGLE_CLOUD_PROJECT});
}

# Get Kubernetes configuration
sub k8s_namespace ($self) {
    return $self->get('kubernetes.namespace', 'default');
}

# Get custom parsers
sub custom_parsers ($self) {
    return $self->get('parsers', []);
}

# Get aliases
sub aliases ($self) {
    return $self->get('aliases', {});
}

# Expand an alias if it exists
sub expand_alias ($self, $name) {
    my $aliases = $self->aliases;
    return $aliases->{$name} if exists $aliases->{$name};
    return undef;
}

# Check if colors are enabled
sub colors_enabled ($self) {
    return 0 if $ENV{NO_COLOR};
    return $self->get('output.color', 1);
}

1;

__END__

=head1 NAME

Sift::Config - Configuration management for Sift Pro

=head1 SYNOPSIS

    use Sift::Config;

    my $config = Sift::Config->new;

    # Get specific values
    my $output = $config->default_output;
    my $limit = $config->default_limit;

    # Get nested values with dot notation
    my $region = $config->get('aws.region', 'us-east-1');

=head1 DESCRIPTION

Manages configuration for Sift Pro from files and environment variables.

=head1 CONFIG FILE FORMAT

Configuration files use YAML format:

    # ~/.ptxrc
    defaults:
      output: pretty
      limit: 100

    aws:
      profile: production
      region: us-west-2

    gcp:
      project: my-project-id

    kubernetes:
      namespace: production

    output:
      color: true

    aliases:
      errors: "status >= 500"
      slow: "duration > 1000"

=head1 CONFIG FILE LOCATIONS

Configuration is loaded from the first file found:

=over 4

=item * C<$PTX_CONFIG> environment variable

=item * C<.ptxrc> (current directory)

=item * C<.ptx.yml> (current directory)

=item * C<~/.ptxrc>

=item * C<~/.config/ptx/config.yml>

=item * C</etc/ptx/config.yml>

=back

=head1 ENVIRONMENT VARIABLES

=over 4

=item * C<PTX_CONFIG> - Path to config file

=item * C<NO_COLOR> - Disable colored output

=item * C<AWS_PROFILE> - AWS profile name

=item * C<AWS_DEFAULT_REGION> - AWS region

=item * C<GOOGLE_CLOUD_PROJECT> - GCP project ID

=back

=cut
