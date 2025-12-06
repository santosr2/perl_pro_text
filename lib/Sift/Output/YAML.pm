package Sift::Output::YAML;
use v5.36;
use Moo;
use YAML::XS qw(Dump);
use namespace::autoclean;

with 'Sift::Output::Base';

sub format_name ($self) { 'yaml' }

sub format ($self, $events) {
    my @data = map { $self->_event_to_hash($_) } $events->@*;
    return Dump(\@data);
}

sub format_single ($self, $event) {
    return Dump($self->_event_to_hash($event));
}

sub _event_to_hash ($self, $event) {
    # Handle both Event objects and plain hashrefs (from aggregations)
    if (ref $event eq 'HASH') {
        return $event;
    }

    return {
        timestamp => $self->format_timestamp($event->timestamp),
        source    => $event->source,
        $event->fields->%*,
    };
}

1;

__END__

=head1 NAME

Sift::Output::YAML - Format events as YAML

=head1 SYNOPSIS

    use Sift::Output::YAML;

    my $formatter = Sift::Output::YAML->new;
    print $formatter->format($events);

=head1 DESCRIPTION

Formats log events as YAML documents.

=cut
