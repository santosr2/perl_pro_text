use v5.36;
use Test2::V0;
use Path::Tiny;
use PerlText::Event;
use PerlText::Parser::Detector;
use PerlText::Parser::Nginx;
use PerlText::Parser::JSON;
use PerlText::Parser::Syslog;
use PerlText::Parser::Custom;
use PerlText::Query::Parser;
use PerlText::Query::Executor;
use PerlText::Transform::Engine;
use PerlText::Transform::Eval;
use PerlText::Transform::Aggregator;
use PerlText::Query::AST;
use PerlText::Output::Table;
use PerlText::Output::JSON;
use PerlText::Output::CSV;

# Test full pipelines: Source → Parse → Query → Transform → Output

subtest 'Nginx pipeline: parse → filter → output' => sub {
    # Sample nginx logs
    my @nginx_lines = (
        '192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /api/users HTTP/1.1" 200 1234 "-" "Mozilla/5.0"',
        '192.168.1.2 - - [04/Dec/2025:10:00:01 +0000] "POST /api/login HTTP/1.1" 401 89 "-" "curl/7.68.0"',
        '192.168.1.3 - - [04/Dec/2025:10:00:02 +0000] "GET /api/admin HTTP/1.1" 500 456 "-" "Mozilla/5.0"',
        '192.168.1.1 - - [04/Dec/2025:10:00:03 +0000] "GET /health HTTP/1.1" 200 15 "-" "kube-probe"',
    );

    # Parse
    my $parser = PerlText::Parser::Nginx->new;
    my $events = $parser->parse_lines(\@nginx_lines);
    is scalar(@$events), 4, 'parsed 4 events';

    # Query: filter errors
    my $qp = PerlText::Query::Parser->new;
    my ($ast, $err) = $qp->try_parse('status >= 400');
    ok !$err, 'query parsed successfully';

    my $executor = PerlText::Query::Executor->new(events => $events);
    my $filtered = $executor->execute($ast);
    is scalar(@$filtered), 2, 'filtered to 2 error events';
    is $filtered->[0]->get('status'), 401, 'first error is 401';
    is $filtered->[1]->get('status'), 500, 'second error is 500';

    # Output as JSON
    my $json_out = PerlText::Output::JSON->new;
    my $output = $json_out->format($filtered);
    like $output, qr/"status"/, 'JSON output contains status';
};

subtest 'JSON pipeline: parse → transform → aggregate' => sub {
    my @json_lines = (
        '{"level":"error","service":"api","latency":150}',
        '{"level":"error","service":"api","latency":200}',
        '{"level":"info","service":"web","latency":50}',
        '{"level":"error","service":"web","latency":300}',
    );

    # Parse
    my $parser = PerlText::Parser::JSON->new;
    my $events = $parser->parse_lines(\@json_lines);
    is scalar(@$events), 4, 'parsed 4 events';

    # Transform: add latency_ms field
    my $transform = PerlText::Transform::Eval->new(
        code => '$latency_ms = $latency * 1'
    );
    my $engine = PerlText::Transform::Engine->new(transforms => [$transform]);
    my $transformed = $engine->apply($events);
    ok $transformed->[0]->get('latency_ms'), 'transform added latency_ms';

    # Query: filter errors
    my $qp = PerlText::Query::Parser->new;
    my ($ast, $err) = $qp->try_parse('level == "error"');
    ok !$err, 'query parsed';

    my $executor = PerlText::Query::Executor->new(events => $transformed);
    my $errors = $executor->execute($ast);
    is scalar(@$errors), 3, 'filtered to 3 error events';

    # Aggregate: count by service
    my $agg = PerlText::Transform::Aggregator->new(
        group_by     => ['service'],
        aggregations => [
            PerlText::Query::AST::Aggregation->new(func => 'count'),
        ],
    );
    my $counted = $agg->aggregate($errors);
    is scalar(@$counted), 2, 'grouped into 2 services';
    is $counted->[0]{count} + $counted->[1]{count}, 3, 'total count is 3';
};

subtest 'Auto-detect pipeline: detect → parse → filter' => sub {
    my @mixed_lines = (
        '{"level":"info","message":"startup"}',
        '{"level":"error","message":"failed"}',
    );

    # Auto-detect format
    my $detector = PerlText::Parser::Detector->new;
    my $parser = $detector->detect(\@mixed_lines);
    ok $parser, 'detected a parser';
    is $parser->format_name, 'json', 'detected JSON format';

    # Parse and filter
    my $events = $parser->parse_lines(\@mixed_lines);
    is scalar(@$events), 2, 'parsed 2 events';

    my $qp = PerlText::Query::Parser->new;
    my ($ast, $err) = $qp->try_parse('level == "error"');
    my $executor = PerlText::Query::Executor->new(events => $events);
    my $filtered = $executor->execute($ast);
    is scalar(@$filtered), 1, 'filtered to 1 error';
    is $filtered->[0]->get('message'), 'failed', 'correct error message';
};

subtest 'Custom parser pipeline' => sub {
    my @custom_lines = (
        '[2025-12-04 10:00:00] ERROR user=alice action=login result=failed',
        '[2025-12-04 10:00:01] INFO user=bob action=login result=success',
        '[2025-12-04 10:00:02] ERROR user=charlie action=delete result=denied',
    );

    # Create custom parser
    my $parser = PerlText::Parser::Custom->new(
        name    => 'audit',
        pattern => qr{
            ^\[(?<timestamp>[^\]]+)\]
            \s+(?<level>\w+)
            \s+user=(?<user>\w+)
            \s+action=(?<action>\w+)
            \s+result=(?<result>\w+)
        }x,
        field_types => {
            level => 'upper',
        },
    );

    my $events = $parser->parse_lines(\@custom_lines);
    is scalar(@$events), 3, 'parsed 3 events';
    is $events->[0]->get('level'), 'ERROR', 'level uppercased';
    is $events->[0]->get('user'), 'alice', 'extracted user';

    # Filter errors
    my $qp = PerlText::Query::Parser->new;
    my ($ast, $err) = $qp->try_parse('level == "ERROR"');
    my $executor = PerlText::Query::Executor->new(events => $events);
    my $errors = $executor->execute($ast);
    is scalar(@$errors), 2, 'found 2 errors';

    # Aggregate by action
    my $agg = PerlText::Transform::Aggregator->new(
        group_by     => ['action'],
        aggregations => [
            PerlText::Query::AST::Aggregation->new(func => 'count'),
        ],
    );
    my $by_action = $agg->aggregate($errors);
    is scalar(@$by_action), 2, 'grouped by 2 actions';
};

subtest 'Syslog pipeline: parse → query with AND' => sub {
    my @syslog_lines = (
        'Dec  4 10:00:00 server1 sshd[1234]: Connection from 192.168.1.1',
        'Dec  4 10:00:01 server1 sshd[1234]: Accepted publickey for root',
        'Dec  4 10:00:02 server2 nginx[5678]: error: connection refused',
        'Dec  4 10:00:03 server1 cron[9999]: job completed',
    );

    # Parse
    my $parser = PerlText::Parser::Syslog->new;
    my $events = $parser->parse_lines(\@syslog_lines);
    is scalar(@$events), 4, 'parsed 4 events';

    # Query: sshd on server1 (syslog uses 'hostname' not 'host')
    my $qp = PerlText::Query::Parser->new;
    my ($ast, $err) = $qp->try_parse('program == "sshd" and hostname == "server1"');
    ok !$err, 'complex query parsed';

    my $executor = PerlText::Query::Executor->new(events => $events);
    my $filtered = $executor->execute($ast);
    is scalar(@$filtered), 2, 'found 2 sshd events on server1';
};

subtest 'Multiple output formats' => sub {
    my @events = (
        PerlText::Event->new(
            timestamp => 1733320800,
            source    => 'test',
            fields    => { name => 'Alice', score => 95 },
        ),
        PerlText::Event->new(
            timestamp => 1733320801,
            source    => 'test',
            fields    => { name => 'Bob', score => 87 },
        ),
    );

    # Table output
    my $table = PerlText::Output::Table->new->format(\@events);
    like $table, qr/Alice/, 'table has Alice';
    like $table, qr/Bob/, 'table has Bob';

    # JSON output
    my $json = PerlText::Output::JSON->new->format(\@events);
    like $json, qr/"name"/, 'JSON has name field';
    like $json, qr/"score"/, 'JSON has score field';

    # CSV output
    my $csv = PerlText::Output::CSV->new->format(\@events);
    like $csv, qr/name/, 'CSV has name header';
    like $csv, qr/Alice/, 'CSV has Alice';
};

subtest 'Full pipeline with aggregation query' => sub {
    my @json_lines = (
        '{"ip":"1.1.1.1","status":200}',
        '{"ip":"1.1.1.1","status":500}',
        '{"ip":"2.2.2.2","status":200}',
        '{"ip":"1.1.1.1","status":404}',
        '{"ip":"2.2.2.2","status":500}',
    );

    # Parse
    my $parser = PerlText::Parser::JSON->new;
    my $events = $parser->parse_lines(\@json_lines);

    # Query with aggregation
    my $qp = PerlText::Query::Parser->new;
    my ($ast, $err) = $qp->try_parse('status >= 400 group by ip count');
    ok !$err, 'aggregation query parsed';

    my $executor = PerlText::Query::Executor->new(events => $events);
    my $results = $executor->execute($ast);

    # Results should be aggregated hashrefs
    is scalar(@$results), 2, 'got 2 IP groups';

    # Find counts
    my %by_ip = map { $_->{ip} => $_->{count} } @$results;
    is $by_ip{'1.1.1.1'}, 2, '1.1.1.1 has 2 errors';
    is $by_ip{'2.2.2.2'}, 1, '2.2.2.2 has 1 error';
};

subtest 'Transform chain pipeline' => sub {
    my @events = (
        PerlText::Event->new(
            timestamp => time(),
            source    => 'test',
            fields    => { duration => '1.5', status => '200' },
        ),
    );

    # Chain multiple transforms
    my $t1 = PerlText::Transform::Eval->new(code => '$duration_ms = $duration * 1000');
    my $t2 = PerlText::Transform::Eval->new(code => '$status = int($status)');

    my $engine = PerlText::Transform::Engine->new(transforms => [$t1, $t2]);
    my $result = $engine->apply(\@events);

    is $result->[0]->get('duration_ms'), 1500, 'first transform applied';
    is $result->[0]->get('status'), 200, 'second transform applied (int coercion)';
};

subtest 'Empty results handling' => sub {
    my @events = (
        PerlText::Event->new(
            timestamp => time(),
            source    => 'test',
            fields    => { level => 'info' },
        ),
    );

    # Query that matches nothing
    my $qp = PerlText::Query::Parser->new;
    my ($ast, $err) = $qp->try_parse('level == "error"');
    my $executor = PerlText::Query::Executor->new(events => \@events);
    my $filtered = $executor->execute($ast);

    is scalar(@$filtered), 0, 'no matches';

    # Output empty results
    my $table = PerlText::Output::Table->new->format($filtered);
    ok defined $table, 'table handles empty results';

    my $json = PerlText::Output::JSON->new->format($filtered);
    ok defined $json, 'JSON handles empty results';
};

done_testing;
