package PerlText::Output::JSON;
use v5.36;
use Moo;
use JSON::MaybeXS qw(encode_json);
use namespace::autoclean;

with 'PerlText::Output::Base';

has pretty => (
    is      => 'ro',
    default => 0,
);

has jsonl => (
    is      => 'ro',
    default => 1,  # Default to JSONL (one object per line)
);

sub format ($self, $items) {
    return '' unless $items && $items->@*;

    my @hashes = map { $self->format_event($_) } $items->@*;

    if ($self->jsonl) {
        return join("\n", map { encode_json($_) } @hashes) . "\n";
    }

    if ($self->pretty) {
        my $json = JSON::MaybeXS->new(
            utf8         => 1,
            pretty       => 1,
            canonical    => 1,
        );
        return $json->encode(\@hashes);
    }

    return encode_json(\@hashes) . "\n";
}

1;

__END__

=head1 NAME

PerlText::Output::JSON - JSON/JSONL output formatter

=head1 SYNOPSIS

    use PerlText::Output::JSON;

    # JSONL format (default)
    my $formatter = PerlText::Output::JSON->new;
    print $formatter->format(\@events);

    # Pretty JSON array
    my $formatter = PerlText::Output::JSON->new(
        jsonl  => 0,
        pretty => 1,
    );

=head1 ATTRIBUTES

=head2 jsonl

Output as JSON Lines (one object per line). Default: true.

=head2 pretty

Pretty-print JSON (only when jsonl is false). Default: false.

=cut
