use v5.36;
use Test2::V0;
use PerlText::Parser::Detector;

my $detector = PerlText::Parser::Detector->new;

subtest 'detect nginx format' => sub {
    my @lines = (
        '192.168.1.1 - - [04/Dec/2025:10:00:00 +0000] "GET /api/users HTTP/1.1" 200 1234 "-" "Mozilla/5.0"',
        '192.168.1.2 - - [04/Dec/2025:10:00:01 +0000] "POST /api/login HTTP/1.1" 401 89 "-" "curl/7.68.0"',
    );

    my $parser = $detector->detect(\@lines);
    ok defined $parser, 'detected a parser';
    is $parser->format_name, 'nginx', 'detected nginx format';
};

subtest 'detect JSON format' => sub {
    my @lines = (
        '{"level":"info","message":"Server started","timestamp":"2025-12-04T10:00:00Z"}',
        '{"level":"error","message":"Connection failed","status":500}',
    );

    my $parser = $detector->detect(\@lines);
    ok defined $parser, 'detected a parser';
    is $parser->format_name, 'json', 'detected JSON format';
};

subtest 'detect syslog BSD format' => sub {
    my @lines = (
        'Dec  4 10:00:00 myhost sshd[1234]: Connection from 192.168.1.1',
        'Dec  4 10:00:01 myhost sshd[1234]: Accepted publickey for user',
    );

    my $parser = $detector->detect(\@lines);
    ok defined $parser, 'detected a parser';
    is $parser->format_name, 'syslog', 'detected syslog format';
};

subtest 'detect syslog RFC5424 format' => sub {
    my @lines = (
        '<134>1 2025-12-04T10:00:00Z myhost myapp 1234 ID47 - Application started',
        '<134>1 2025-12-04T10:00:01Z myhost myapp 1234 ID48 - Processing request',
    );

    my $parser = $detector->detect(\@lines);
    ok defined $parser, 'detected a parser';
    is $parser->format_name, 'syslog', 'detected syslog format';
};

subtest 'returns undef for unknown format' => sub {
    my @lines = (
        'This is just random text that does not match any format',
        'Another line of unstructured content here',
    );

    my $parser = $detector->detect(\@lines);
    ok !defined $parser, 'returns undef for unknown format';
};

subtest 'handles empty input' => sub {
    my $parser = $detector->detect([]);
    ok !defined $parser, 'returns undef for empty input';
};

subtest 'available_formats' => sub {
    my $formats = $detector->available_formats;
    ok ref $formats eq 'ARRAY', 'returns arrayref';
    ok grep({ $_ eq 'nginx' } @$formats), 'includes nginx';
    ok grep({ $_ eq 'json' } @$formats), 'includes json';
    ok grep({ $_ eq 'syslog' } @$formats), 'includes syslog';
};

done_testing;
