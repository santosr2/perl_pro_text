use v5.36;
use Test2::V0;
use PerlText::Parser::Nginx;

my $parser = PerlText::Parser::Nginx->new;

subtest 'format_name' => sub {
    is $parser->format_name, 'nginx', 'format name is nginx';
};

subtest 'parse combined log' => sub {
    my $line = '192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /api/users HTTP/1.1" 200 1234 "http://example.com" "Mozilla/5.0"';

    ok $parser->can_parse($line), 'can parse combined format';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    is $event->get('ip'), '192.168.1.1', 'ip extracted';
    is $event->get('method'), 'GET', 'method extracted';
    is $event->get('path'), '/api/users', 'path extracted';
    is $event->get('status'), 200, 'status extracted';
    is $event->get('bytes'), 1234, 'bytes extracted';
    is $event->get('referer'), 'http://example.com', 'referer extracted';
    like $event->get('ua'), qr/Mozilla/, 'user agent extracted';
    is $event->get('format'), 'combined', 'format is combined';
    is $event->source, 'nginx', 'source is nginx';
    is $event->raw, $line, 'raw line stored';
};

subtest 'parse combined log with authenticated user' => sub {
    my $line = '192.168.1.3 - admin [04/Dec/2025:10:00:02 +0000] "GET /admin/dashboard HTTP/1.1" 200 5678 "-" "Mozilla/5.0"';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    is $event->get('user'), 'admin', 'user extracted';
    is $event->get('referer'), '-', 'dash referer handled';
};

subtest 'parse combined log without optional fields' => sub {
    my $line = '10.0.0.1 - - [04/Dec/2025:10:00:00 +0000] "POST /api HTTP/1.1" 201 42';

    ok $parser->can_parse($line), 'can parse minimal combined format';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    is $event->get('method'), 'POST', 'method extracted';
    is $event->get('status'), 201, 'status extracted';
};

subtest 'parse error log' => sub {
    my $line = '2025/12/04 10:00:00 [error] 1234#5678: *90 connect() failed (111: Connection refused)';

    ok $parser->can_parse($line), 'can parse error format';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    is $event->get('level'), 'error', 'level extracted';
    is $event->get('pid'), 1234, 'pid extracted';
    is $event->get('tid'), 5678, 'tid extracted';
    is $event->get('conn'), 90, 'connection id extracted';
    like $event->get('message'), qr/connect.*failed/, 'message extracted';
    is $event->get('format'), 'error', 'format is error';
};

subtest 'parse error log with client IP' => sub {
    my $line = '2025/12/04 10:00:00 [warn] 1234#5678: *90 upstream timed out, client: 192.168.1.50, server: example.com';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    is $event->get('level'), 'warn', 'level extracted';
    is $event->get('client_ip'), '192.168.1.50', 'client IP extracted from message';
};

subtest 'cannot parse non-nginx format' => sub {
    my $line = '{"level":"info","message":"hello"}';
    ok !$parser->can_parse($line), 'cannot parse JSON';
};

subtest 'confidence_score' => sub {
    my @nginx_lines = (
        '192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET / HTTP/1.1" 200 100 "-" "UA"',
        '192.168.1.2 - - [04/Dec/2025:10:00:01 +0000] "POST /api HTTP/1.1" 201 50 "-" "UA"',
    );

    my $score = $parser->confidence_score(\@nginx_lines);
    is $score, 1.0, 'perfect confidence for nginx lines';

    my @mixed = (
        '192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET / HTTP/1.1" 200 100 "-" "UA"',
        '{"level":"info"}',
    );

    $score = $parser->confidence_score(\@mixed);
    is $score, 0.5, '50% confidence for mixed lines';
};

done_testing;
