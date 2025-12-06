use v5.36;
use Test2::V0;
use PerlText::Parser::Apache;

my $parser = PerlText::Parser::Apache->new;

subtest 'format name' => sub {
    is $parser->format_name, 'apache', 'correct format name';
};

subtest 'parse Apache Combined Log Format' => sub {
    my $line = '192.168.1.1 - john [04/Dec/2025:10:15:30 +0000] "GET /api/users HTTP/1.1" 200 1234 "https://example.com/page" "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"';

    my $event = $parser->parse_line($line);
    ok defined $event, 'parsed event';

    is $event->get('ip'), '192.168.1.1', 'correct ip';
    is $event->get('user'), 'john', 'correct user';
    is $event->get('method'), 'GET', 'correct method';
    is $event->get('path'), '/api/users', 'correct path';
    is $event->get('protocol'), 'HTTP/1.1', 'correct protocol';
    is $event->get('status'), 200, 'correct status';
    is $event->get('bytes'), 1234, 'correct bytes';
    is $event->get('referer'), 'https://example.com/page', 'correct referer';
    like $event->get('user_agent'), qr/Mozilla/, 'correct user_agent';
};

subtest 'parse Apache Common Log Format' => sub {
    my $line = '10.0.0.1 - - [04/Dec/2025:10:15:30 +0000] "POST /api/login HTTP/1.1" 401 89';

    my $event = $parser->parse_line($line);
    ok defined $event, 'parsed event';

    is $event->get('ip'), '10.0.0.1', 'correct ip';
    ok !defined $event->get('user'), 'no user (was -)';
    is $event->get('method'), 'POST', 'correct method';
    is $event->get('path'), '/api/login', 'correct path';
    is $event->get('status'), 401, 'correct status';
    is $event->get('bytes'), 89, 'correct bytes';
    ok !defined $event->get('referer'), 'no referer in common format';
    ok !defined $event->get('user_agent'), 'no user_agent in common format';
};

subtest 'parse with empty bytes (-)' => sub {
    my $line = '192.168.1.1 - - [04/Dec/2025:10:15:30 +0000] "HEAD /health HTTP/1.1" 204 -';

    my $event = $parser->parse_line($line);
    ok defined $event, 'parsed event';

    is $event->get('status'), 204, 'correct status';
    ok !defined $event->get('bytes'), 'no bytes for 204 response';
};

subtest 'parse with quoted path containing spaces' => sub {
    my $line = '192.168.1.1 - - [04/Dec/2025:10:15:30 +0000] "GET /path/with%20space HTTP/1.1" 200 100';

    my $event = $parser->parse_line($line);
    ok defined $event, 'parsed event';

    is $event->get('path'), '/path/with%20space', 'correct encoded path';
};

subtest 'parse with referer containing dash' => sub {
    my $line = '192.168.1.1 - - [04/Dec/2025:10:15:30 +0000] "GET / HTTP/1.1" 200 100 "-" "curl/7.68.0"';

    my $event = $parser->parse_line($line);
    ok defined $event, 'parsed event';

    ok !defined $event->get('referer'), 'dash referer becomes undef';
    is $event->get('user_agent'), 'curl/7.68.0', 'correct user_agent';
};

subtest 'confidence score' => sub {
    my @apache_lines = (
        '192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /api HTTP/1.1" 200 1234 "-" "Mozilla/5.0"',
        '192.168.1.2 - - [04/Dec/2025:10:00:01 +0000] "POST /login HTTP/1.1" 401 89 "-" "curl/7.68.0"',
    );

    my $score = $parser->confidence_score(\@apache_lines);
    ok $score >= 0.8, "high confidence for apache logs: $score";
};

subtest 'low confidence for non-apache logs' => sub {
    my @json_lines = (
        '{"level":"info","message":"Server started"}',
        '{"level":"error","status":500}',
    );

    my $score = $parser->confidence_score(\@json_lines);
    ok $score < 0.2, "low confidence for JSON logs: $score";
};

subtest 'parse_lines' => sub {
    my @lines = (
        '192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /api HTTP/1.1" 200 100',
        '',  # Empty line should be skipped
        '192.168.1.2 - - [04/Dec/2025:10:00:01 +0000] "POST /login HTTP/1.1" 401 50',
    );

    my $events = $parser->parse_lines(\@lines);
    is scalar(@$events), 2, 'parsed 2 events (skipped empty)';
    is $events->[0]->get('status'), 200, 'first event status';
    is $events->[1]->get('status'), 401, 'second event status';
};

subtest 'handles invalid lines gracefully' => sub {
    my $event = $parser->parse_line('not a valid apache log line');
    ok !defined $event, 'returns undef for invalid line';

    $event = $parser->parse_line('');
    ok !defined $event, 'returns undef for empty line';
};

done_testing;
