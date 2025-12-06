use v5.36;
use Test2::V0;
use Sift::Event;
use Sift::Query::Parser;
use Sift::Query::Executor;

sub make_event (%fields) {
    return Sift::Event->new(
        timestamp => $fields{timestamp} // time(),
        source    => $fields{source} // 'test',
        fields    => \%fields,
    );
}

my @events = (
    make_event(status => 200, method => 'GET',  ip => '192.168.1.1', latency => 50),
    make_event(status => 200, method => 'POST', ip => '192.168.1.2', latency => 100),
    make_event(status => 500, method => 'GET',  ip => '192.168.1.1', latency => 200),
    make_event(status => 404, method => 'GET',  ip => '192.168.1.3', latency => 30),
    make_event(status => 502, method => 'POST', ip => '192.168.1.1', latency => 500),
);

my $parser = Sift::Query::Parser->new;

subtest 'simple comparison' => sub {
    my $ast = $parser->parse('status >= 500');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 2, 'found 2 events with status >= 500';
};

subtest 'equality comparison' => sub {
    my $ast = $parser->parse('method == "POST"');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 2, 'found 2 POST events';
};

subtest 'AND expression' => sub {
    my $ast = $parser->parse('status >= 500 and method == "GET"');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 1, 'found 1 event matching AND';
    is $results->[0]->get('status'), 500, 'correct event';
};

subtest 'OR expression' => sub {
    my $ast = $parser->parse('status == 404 or status == 502');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 2, 'found 2 events matching OR';
};

subtest 'NOT expression' => sub {
    my $ast = $parser->parse('not status == 200');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 3, 'found 3 non-200 events';
};

subtest 'IN expression' => sub {
    my $ast = $parser->parse('status in {500, 502}');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 2, 'found 2 events with status in set';
};

subtest 'group by with count' => sub {
    my $ast = $parser->parse('status >= 200 group by ip count');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 3, 'found 3 groups';

    # Find the 192.168.1.1 group
    my ($ip1) = grep { $_->{ip} eq '192.168.1.1' } $results->@*;
    is $ip1->{count}, 3, '192.168.1.1 has 3 events';
};

subtest 'group by with avg' => sub {
    my $ast = $parser->parse('ip == "192.168.1.1" group by ip avg latency');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 1, 'found 1 group';
    # (50 + 200 + 500) / 3 = 250
    is $results->[0]{avg_latency}, 250, 'avg latency is 250';
};

subtest 'sort by field' => sub {
    my $ast = $parser->parse('status >= 200 sort by latency desc');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is $results->[0]->get('latency'), 500, 'highest latency first';
    is $results->[-1]->get('latency'), 30, 'lowest latency last';
};

subtest 'limit results' => sub {
    my $ast = $parser->parse('status >= 200 limit 2');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 2, 'limited to 2 results';
};

subtest 'combined query' => sub {
    my $ast = $parser->parse('status >= 200 group by method count sort by count desc limit 1');
    my $exec = Sift::Query::Executor->new(events => \@events);
    my $results = $exec->execute($ast);

    is scalar($results->@*), 1, 'limited to 1 result';
    is $results->[0]{method}, 'GET', 'GET has most events';
    is $results->[0]{count}, 3, 'GET has 3 events';
};

done_testing;
