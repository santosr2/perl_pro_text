use v5.36;
use Test2::V0;
use PerlText::Event;

subtest 'basic event creation' => sub {
    my $event = PerlText::Event->new(
        timestamp => 1733310000,
        source    => 'nginx',
    );

    is $event->timestamp, 1733310000, 'timestamp set';
    is $event->source, 'nginx', 'source set';
    is ref($event->fields), 'HASH', 'fields is hashref';
    ok !defined $event->raw, 'raw is undefined';
};

subtest 'event with fields' => sub {
    my $event = PerlText::Event->new(
        timestamp => 1733310000,
        source    => 'nginx',
        fields    => {
            status => 200,
            method => 'GET',
            path   => '/api/users',
        },
        raw => 'the raw log line',
    );

    is $event->get('status'), 200, 'get status';
    is $event->get('method'), 'GET', 'get method';
    is $event->get('path'), '/api/users', 'get path';
    is $event->raw, 'the raw log line', 'raw set';
};

subtest 'set and has_field' => sub {
    my $event = PerlText::Event->new(
        timestamp => 1733310000,
        source    => 'test',
    );

    ok !$event->has_field('foo'), 'foo does not exist';

    $event->set('foo', 'bar');
    ok $event->has_field('foo'), 'foo exists after set';
    is $event->get('foo'), 'bar', 'get returns set value';
};

subtest 'field_names' => sub {
    my $event = PerlText::Event->new(
        timestamp => 1733310000,
        source    => 'test',
        fields    => { a => 1, b => 2, c => 3 },
    );

    my @names = sort $event->field_names;
    is \@names, [qw(a b c)], 'field_names returns all keys';
};

subtest 'to_hash' => sub {
    my $event = PerlText::Event->new(
        timestamp => 1733310000,
        source    => 'nginx',
        fields    => { status => 200 },
    );

    my $hash = $event->to_hash;
    is $hash->{timestamp}, 1733310000, 'to_hash includes timestamp';
    is $hash->{source}, 'nginx', 'to_hash includes source';
    is $hash->{status}, 200, 'to_hash includes fields';
};

subtest 'clone' => sub {
    my $event = PerlText::Event->new(
        timestamp => 1733310000,
        source    => 'nginx',
        fields    => { status => 200 },
    );

    my $clone = $event->clone;
    is $clone->timestamp, 1733310000, 'clone has same timestamp';
    is $clone->source, 'nginx', 'clone has same source';
    is $clone->get('status'), 200, 'clone has same fields';

    # Modify clone, original unchanged
    $clone->set('status', 500);
    is $event->get('status'), 200, 'original unchanged';
    is $clone->get('status'), 500, 'clone modified';
};

subtest 'clone with overrides' => sub {
    my $event = PerlText::Event->new(
        timestamp => 1733310000,
        source    => 'nginx',
    );

    my $clone = $event->clone(source => 'k8s');
    is $clone->source, 'k8s', 'clone with source override';
    is $clone->timestamp, 1733310000, 'clone keeps timestamp';
};

done_testing;
