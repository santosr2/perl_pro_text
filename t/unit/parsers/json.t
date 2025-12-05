use v5.36;
use Test2::V0;
use PerlText::Parser::JSON;

my $parser = PerlText::Parser::JSON->new;

subtest 'format_name' => sub {
    is $parser->format_name, 'json', 'format name is json';
};

subtest 'parse simple json' => sub {
    my $line = '{"level":"info","message":"hello world"}';

    ok $parser->can_parse($line), 'can parse JSON';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    is $event->get('level'), 'info', 'level extracted';
    is $event->get('message'), 'hello world', 'message extracted';
    is $event->source, 'json', 'source is json';
};

subtest 'parse with timestamp field' => sub {
    my $line = '{"timestamp":"2025-12-04T10:00:00Z","level":"error","message":"fail"}';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    # Timestamp should be parsed from the field
    ok $event->timestamp > 0, 'timestamp is positive';
    is $event->get('level'), 'error', 'level extracted';
};

subtest 'parse with epoch timestamp' => sub {
    my $line = '{"timestamp":1733310000,"level":"warn"}';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    is $event->timestamp, 1733310000, 'epoch timestamp used';
};

subtest 'parse with nested objects' => sub {
    my $line = '{"request":{"method":"GET","path":"/api"},"response":{"status":200}}';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    is $event->get('request.method'), 'GET', 'nested method extracted';
    is $event->get('request.path'), '/api', 'nested path extracted';
    is $event->get('response.status'), 200, 'nested status extracted';
};

subtest 'parse with arrays' => sub {
    my $line = '{"tags":["web","api"],"level":"info"}';

    my $event = $parser->parse($line);
    ok defined $event, 'parse returns event';

    is ref($event->get('tags')), 'ARRAY', 'tags is array';
    is $event->get('tags')->[0], 'web', 'first tag';
};

subtest 'cannot parse non-json' => sub {
    ok !$parser->can_parse('not json'), 'cannot parse plain text';
    ok !$parser->can_parse('192.168.1.1 - -'), 'cannot parse nginx';
};

subtest 'invalid json returns undef' => sub {
    my $event = $parser->parse('{invalid json}');
    ok !defined $event, 'invalid json returns undef';
};

subtest 'confidence_score' => sub {
    my @json_lines = (
        '{"level":"info","message":"one"}',
        '{"level":"error","message":"two"}',
    );

    my $score = $parser->confidence_score(\@json_lines);
    is $score, 1.0, 'perfect confidence for JSON lines';
};

done_testing;
