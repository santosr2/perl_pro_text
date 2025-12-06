use v5.36;
use Test2::V0;
use Sift::Event;
use Sift::Transform::Engine;
use Sift::Transform::Eval;
use Sift::Transform::Aggregator;
use Sift::Query::AST;

subtest 'Transform::Eval basic operations' => sub {
    my $event = Sift::Event->new(
        timestamp => time(),
        source    => 'test',
        fields    => { status => 500, message => 'error occurred' },
    );

    my $transform = Sift::Transform::Eval->new(code => '$status = $status + 1');
    my $result = $transform->apply($event);

    is $result->get('status'), 501, 'numeric modification works';
    is $result->get('message'), 'error occurred', 'other fields unchanged';
};

subtest 'Transform::Eval string operations' => sub {
    my $event = Sift::Event->new(
        timestamp => time(),
        source    => 'test',
        fields    => { level => 'error', path => '/api/users' },
    );

    my $transform = Sift::Transform::Eval->new(code => '$level = uc($level)');
    my $result = $transform->apply($event);

    is $result->get('level'), 'ERROR', 'string uppercase works';
};

subtest 'Transform::Eval add new field' => sub {
    my $event = Sift::Event->new(
        timestamp => time(),
        source    => 'test',
        fields    => { duration_sec => 2.5 },
    );

    my $transform = Sift::Transform::Eval->new(code => '$duration_ms = $duration_sec * 1000');
    my $result = $transform->apply($event);

    is $result->get('duration_ms'), 2500, 'computed field added';
    is $result->get('duration_sec'), 2.5, 'original field unchanged';
};

subtest 'Transform::Engine pipeline' => sub {
    my @events = map {
        Sift::Event->new(
            timestamp => time(),
            source    => 'test',
            fields    => { value => $_ },
        )
    } (1, 2, 3);

    my $engine = Sift::Transform::Engine->new;
    $engine->add_transform(Sift::Transform::Eval->new(code => '$value = $value * 2'));
    $engine->add_transform(Sift::Transform::Eval->new(code => '$value = $value + 10'));

    my $results = $engine->apply(\@events);

    is scalar(@$results), 3, 'all events processed';
    is $results->[0]->get('value'), 12, 'first: (1*2)+10 = 12';
    is $results->[1]->get('value'), 14, 'second: (2*2)+10 = 14';
    is $results->[2]->get('value'), 16, 'third: (3*2)+10 = 16';
};

subtest 'Transform::Aggregator count' => sub {
    my @events = map {
        Sift::Event->new(
            timestamp => time(),
            source    => 'test',
            fields    => { ip => $_ },
        )
    } ('1.1.1.1', '1.1.1.1', '2.2.2.2', '1.1.1.1');

    my $agg = Sift::Transform::Aggregator->new(
        group_by     => ['ip'],
        aggregations => [
            Sift::Query::AST::Aggregation->new(func => 'count'),
        ],
    );

    my $results = $agg->aggregate(\@events);

    is scalar(@$results), 2, 'two groups';

    my %by_ip = map { $_->{ip} => $_->{count} } @$results;
    is $by_ip{'1.1.1.1'}, 3, 'ip 1.1.1.1 count is 3';
    is $by_ip{'2.2.2.2'}, 1, 'ip 2.2.2.2 count is 1';
};

subtest 'Transform::Aggregator sum and avg' => sub {
    my @events = map {
        Sift::Event->new(
            timestamp => time(),
            source    => 'test',
            fields    => { category => 'A', value => $_ },
        )
    } (10, 20, 30);

    my $agg = Sift::Transform::Aggregator->new(
        group_by     => ['category'],
        aggregations => [
            Sift::Query::AST::Aggregation->new(func => 'count'),
            Sift::Query::AST::Aggregation->new(func => 'sum', field => 'value'),
            Sift::Query::AST::Aggregation->new(func => 'avg', field => 'value'),
        ],
    );

    my $results = $agg->aggregate(\@events);

    is scalar(@$results), 1, 'one group';
    is $results->[0]{count}, 3, 'count is 3';
    is $results->[0]{sum_value}, 60, 'sum is 60';
    is $results->[0]{avg_value}, 20, 'avg is 20';
};

subtest 'Transform::Aggregator min and max' => sub {
    my @events = map {
        Sift::Event->new(
            timestamp => time(),
            source    => 'test',
            fields    => { status => $_ },
        )
    } (200, 404, 500, 201, 503);

    my $agg = Sift::Transform::Aggregator->new(
        group_by     => [],
        aggregations => [
            Sift::Query::AST::Aggregation->new(func => 'min', field => 'status'),
            Sift::Query::AST::Aggregation->new(func => 'max', field => 'status'),
        ],
    );

    my $results = $agg->aggregate(\@events);

    is $results->[0]{min_status}, 200, 'min is 200';
    is $results->[0]{max_status}, 503, 'max is 503';
};

done_testing;
