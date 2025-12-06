use v5.36;
use Test2::V0;
use Path::Tiny;
use IPC::Run3;
use JSON::MaybeXS;

my $bin = path(__FILE__)->parent->parent->parent->child('bin/ptx')->stringify;
my $lib = path(__FILE__)->parent->parent->parent->child('lib')->stringify;
my $fixtures = path(__FILE__)->parent->parent->child('fixtures');

sub run_ptx (@args) {
    my ($stdout, $stderr);
    my @cmd = ($^X, "-I$lib", $bin, @args);
    run3 \@cmd, undef, \$stdout, \$stderr;
    return ($stdout, $stderr, $?);
}

sub run_ptx_with_stdin ($input, @args) {
    my ($stdout, $stderr);
    my @cmd = ($^X, "-I$lib", $bin, @args);
    run3 \@cmd, \$input, \$stdout, \$stderr;
    return ($stdout, $stderr, $?);
}

subtest 'help command' => sub {
    my ($out, $err, $exit) = run_ptx('--help');
    is $exit, 0, 'exit code 0';
    like $out, qr/ptx/, 'shows program name';
    like $out, qr/query/, 'shows query command';
};

subtest 'version command' => sub {
    my ($out, $err, $exit) = run_ptx('--version');
    is $exit, 0, 'exit code 0';
    like $out, qr/ptx version/, 'shows version';
};

subtest 'formats command' => sub {
    my ($out, $err, $exit) = run_ptx('formats');
    is $exit, 0, 'exit code 0';
    like $out, qr/nginx/, 'lists nginx';
    like $out, qr/json/, 'lists json';
    like $out, qr/syslog/, 'lists syslog';
};

subtest 'sources command' => sub {
    my ($out, $err, $exit) = run_ptx('sources');
    is $exit, 0, 'exit code 0';
    like $out, qr/file/, 'lists file';
    like $out, qr/k8s/, 'lists k8s';
    like $out, qr/aws/, 'lists aws';
};

subtest 'query with JSON input' => sub {
    my $input = qq{{"level":"error","status":500}\n{"level":"info","status":200}\n};
    my ($out, $err, $exit) = run_ptx_with_stdin($input, 'query', 'status >= 400');

    is $exit, 0, 'exit code 0';
    like $out, qr/500/, 'output contains 500';
    unlike $out, qr/\b200\b.*info/s, 'output does not contain 200 info row';
};

subtest 'query with JSON output' => sub {
    my $input = qq{{"level":"error","status":500}\n};
    my ($out, $err, $exit) = run_ptx_with_stdin($input, 'query', '-o', 'json', 'status >= 400');

    is $exit, 0, 'exit code 0';
    like $out, qr/"status"/, 'output contains status';

    # JSONL format: one JSON object per line
    my @lines = grep { /\S/ && /^\{/ } split /\n/, $out;
    ok @lines >= 1, 'has at least one JSON line';

    if (@lines) {
        my $parsed = eval { JSON::MaybeXS::decode_json($lines[0]) };
        ok !$@, 'first line is valid JSON: ' . ($@ // 'ok');
    }
};

subtest 'query with CSV output' => sub {
    my $input = qq{{"level":"error","status":500}};
    my ($out, $err, $exit) = run_ptx_with_stdin($input, 'query', '-o', 'csv', 'status >= 400');

    is $exit, 0, 'exit code 0';
    my @lines = split /\n/, $out;
    ok @lines >= 2, 'has header and data';
};

subtest 'query with file input' => sub {
    skip_all 'fixture not found' unless $fixtures->child('nginx_access.log')->exists;

    my $file = $fixtures->child('nginx_access.log')->stringify;
    my ($out, $err, $exit) = run_ptx('query', 'status >= 400', $file);

    is $exit, 0, 'exit code 0';
    like $out, qr/\d{3}/, 'output contains status codes';
};

subtest 'query with aggregation' => sub {
    my $input = qq{{"ip":"1.1.1.1","status":500}\n{"ip":"1.1.1.1","status":501}\n{"ip":"2.2.2.2","status":500}\n};
    my ($out, $err, $exit) = run_ptx_with_stdin($input, 'query', '-o', 'json', 'status >= 400 group by ip count');

    is $exit, 0, 'exit code 0';

    # JSONL format: parse each line
    my @lines = grep { /\S/ } split /\n/, $out;
    is scalar(@lines), 2, 'two groups (two lines)';

    for my $line (@lines) {
        my $parsed = eval { JSON::MaybeXS::decode_json($line) };
        ok !$@, 'valid JSON line';
        ok exists $parsed->{count}, 'has count field';
    }
};

subtest 'invalid query syntax' => sub {
    my $input = qq{{"status":500}};
    my ($out, $err, $exit) = run_ptx_with_stdin($input, 'query', 'invalid @@@ syntax');

    isnt $exit, 0, 'non-zero exit code';
    like $err, qr/error/i, 'error message in stderr';
};

subtest 'find command' => sub {
    my $input = qq{{"message":"error occurred","level":"error"}\n{"message":"all good","level":"info"}\n};
    my ($out, $err, $exit) = run_ptx_with_stdin($input, 'find', 'error');

    is $exit, 0, 'exit code 0';
    like $out, qr/error/, 'found error line';
};

done_testing;
