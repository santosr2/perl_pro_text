package Sift::Source::GCP::Logging;
use v5.36;
use Moo;
use Types::Standard qw(Str Maybe Int);
use IPC::Run3;
use JSON::MaybeXS qw(decode_json);
use Sift::Event;
use namespace::autoclean;

with 'Sift::Source::Base';

has project => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has filter => (
    is      => 'ro',
    isa     => Str,
    default => '',
);

has limit => (
    is      => 'ro',
    isa     => Int,
    default => 1000,
);

has freshness => (
    is      => 'ro',
    isa     => Str,
    default => '1h',
);

sub source_type ($self) { 'gcp' }

sub _build_source_name ($self) {
    return 'gcp:' . $self->project;
}

sub fetch_events ($self, %opts) {
    my @cmd = $self->_build_command(%opts);

    my ($stdout, $stderr);
    run3 \@cmd, undef, \$stdout, \$stderr;

    if ($?) {
        my $exit_code = $? >> 8;
        die "gcloud logging failed (exit $exit_code): $stderr\n" if $exit_code;
    }

    my $data = eval { decode_json($stdout) };
    return [] if $@ || !$data || ref $data ne 'ARRAY';

    my @events;
    for my $entry ($data->@*) {
        push @events, $self->_to_event($entry);
    }

    return \@events;
}

sub _build_command ($self, %opts) {
    my @cmd = (
        'gcloud', 'logging', 'read',
        '--project', $self->project,
        '--format', 'json',
        '--limit', $self->limit,
        '--freshness', $self->freshness,
    );

    push @cmd, $self->filter if $self->filter;

    return @cmd;
}

sub _to_event ($self, $entry) {
    my $timestamp = $self->_parse_timestamp($entry->{timestamp});
    my $severity  = $entry->{severity} // 'DEFAULT';

    my $fields = {
        severity    => $severity,
        logName     => $entry->{logName},
        insertId    => $entry->{insertId},
    };

    # Extract resource labels
    if (my $resource = $entry->{resource}) {
        $fields->{resourceType} = $resource->{type};
        if (my $labels = $resource->{labels}) {
            for my $key (keys $labels->%*) {
                $fields->{"resource.$key"} = $labels->{$key};
            }
        }
    }

    # Extract payload
    my $raw = '';
    if (my $text = $entry->{textPayload}) {
        $raw = $text;
        $fields->{message} = $text;
    }
    elsif (my $json = $entry->{jsonPayload}) {
        $raw = JSON::MaybeXS->new->encode($json);
        my %flattened = $self->_flatten($json);
        $fields = { %$fields, %flattened };
    }

    # Extract labels
    if (my $labels = $entry->{labels}) {
        for my $key (keys $labels->%*) {
            $fields->{"label.$key"} = $labels->{$key};
        }
    }

    return Sift::Event->new(
        timestamp => $timestamp,
        source    => $self->source_name,
        raw       => $raw,
        fields    => $fields,
    );
}

sub _parse_timestamp ($self, $ts) {
    return time() unless $ts;

    # GCP timestamps are in RFC3339 format
    if ($ts =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/) {
        require Time::Local;
        my ($y, $m, $d, $h, $min, $s) = ($1, $2, $3, $4, $5, $6);
        return eval { Time::Local::timegm($s, $min, $h, $d, $m - 1, $y) } // time();
    }

    return time();
}

sub _flatten ($self, $data, $prefix = '') {
    my %fields;

    for my $key (keys $data->%*) {
        my $full_key = $prefix ? "${prefix}.${key}" : $key;
        my $value    = $data->{$key};

        if (ref $value eq 'HASH') {
            my %nested = $self->_flatten($value, $full_key);
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

Sift::Source::GCP::Logging - Fetch logs from GCP Cloud Logging

=head1 SYNOPSIS

    use Sift::Source::GCP::Logging;

    my $source = Sift::Source::GCP::Logging->new(
        project => 'my-gcp-project',
        filter  => 'severity >= ERROR',
    );

    my $events = $source->fetch_events;

=head1 DESCRIPTION

Fetches logs from Google Cloud Logging using the gcloud CLI.

=head1 ATTRIBUTES

=head2 project

Required. GCP project ID.

=head2 filter

GCP logging filter expression.

=head2 limit

Maximum entries. Default: 1000.

=head2 freshness

How far back to look. Default: '1h'.

=cut
