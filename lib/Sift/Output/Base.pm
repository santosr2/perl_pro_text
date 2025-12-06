package Sift::Output::Base;
use v5.36;
use Moo::Role;
use POSIX qw(strftime);
use namespace::autoclean;

requires 'format';

sub format_timestamp ($self, $epoch) {
    return strftime('%Y-%m-%d %H:%M:%S', localtime($epoch));
}

sub format_event ($self, $event) {
    if (ref $event eq 'HASH') {
        return $event;
    }
    return $event->to_hash;
}

sub extract_columns ($self, $items) {
    my %cols;
    for my $item ($items->@*) {
        my $hash = $self->format_event($item);
        $cols{$_} = 1 for keys $hash->%*;
    }
    # Order columns sensibly: timestamp first, then alphabetically
    my @ordered = sort {
        return -1 if $a eq 'timestamp';
        return 1  if $b eq 'timestamp';
        return -1 if $a eq 'source';
        return 1  if $b eq 'source';
        return $a cmp $b;
    } keys %cols;
    return @ordered;
}

1;

__END__

=head1 NAME

Sift::Output::Base - Base role for output formatters

=head1 DESCRIPTION

Provides common functionality for output formatters.

=cut
