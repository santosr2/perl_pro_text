package PerlText::Pro;
use v5.36;
use Moo;
use namespace::autoclean;

our $VERSION = '0.01';

use PerlText::Event;
use PerlText::Parser::Detector;
use PerlText::Query::Parser;

has sources => (
    is      => 'ro',
    default => sub { [] },
);

has parser => (
    is      => 'lazy',
    builder => '_build_parser',
);

has query_parser => (
    is      => 'lazy',
    default => sub { PerlText::Query::Parser->new },
);

sub _build_parser ($self) {
    return PerlText::Parser::Detector->new;
}

sub query ($self, $query_string, %opts) {
    my $ast = $self->query_parser->parse($query_string);
    # Execute query against sources
    return $self->_execute_query($ast, %opts);
}

sub _execute_query ($self, $ast, %opts) {
    # Placeholder for query execution
    return [];
}

1;

__END__

=head1 NAME

PerlText::Pro - Unified, intelligent log querying and correlation engine

=head1 SYNOPSIS

    use PerlText::Pro;

    my $ptx = PerlText::Pro->new;
    my $results = $ptx->query('status >= 500 and service == "auth"', since => '1h');

=head1 DESCRIPTION

PerlText Pro is a unified, intelligent log querying and correlation engine.
It searches B<events>, not files, with multi-cloud support, auto-detection
of log formats, and Perl-powered transformations.

Think of it as:

=over 4

=item * ripgrep for log files

=item * jq for structured fields

=item * Splunk-lite for multi-cloud logs

=item * awk-but-friendly for transformations

=item * Perl-powered for flexible patterns

=back

=head1 METHODS

=head2 query

    my $results = $ptx->query($query_string, %options);

Execute a log query and return matching events.

=head1 AUTHOR

Your Name <your.email@example.com>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
