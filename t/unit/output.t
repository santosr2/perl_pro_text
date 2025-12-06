use v5.36;
use Test2::V0;
use PerlText::Event;
use PerlText::Output::Table;
use PerlText::Output::JSON;
use PerlText::Output::CSV;
use PerlText::Output::YAML;
use PerlText::Output::Pretty;
use PerlText::Output::Chart;

my @events = (
    PerlText::Event->new(
        timestamp => 1733320800,  # 2024-12-04 10:00:00
        source    => 'test',
        fields    => { level => 'error', status => 500, message => 'Server error' },
    ),
    PerlText::Event->new(
        timestamp => 1733320860,
        source    => 'test',
        fields    => { level => 'info', status => 200, message => 'OK' },
    ),
);

subtest 'Output::Table' => sub {
    my $formatter = PerlText::Output::Table->new;
    my $output = $formatter->format(\@events);

    ok defined $output, 'produces output';
    like $output, qr/level/, 'contains level header';
    like $output, qr/status/, 'contains status header';
    like $output, qr/500/, 'contains error status';
    like $output, qr/200/, 'contains ok status';
};

subtest 'Output::JSON (JSONL default)' => sub {
    my $formatter = PerlText::Output::JSON->new;
    my $output = $formatter->format(\@events);

    ok defined $output, 'produces output';
    like $output, qr/"level"/, 'contains level key';
    like $output, qr/"error"/, 'contains error value';

    # JSONL: one JSON object per line
    my @lines = grep { /\S/ } split /\n/, $output;
    is scalar(@lines), 2, 'two lines for two events';

    # Each line should be valid JSON
    for my $line (@lines) {
        my $parsed = eval { JSON::MaybeXS::decode_json($line) };
        ok !$@, 'line is valid JSON';
    }
};

subtest 'Output::JSON (array mode)' => sub {
    my $formatter = PerlText::Output::JSON->new(jsonl => 0);
    my $output = $formatter->format(\@events);

    ok defined $output, 'produces output';
    like $output, qr/^\[/, 'starts with array bracket';

    my $parsed = eval { JSON::MaybeXS::decode_json($output) };
    ok !$@, 'valid JSON array';
    is scalar(@$parsed), 2, 'two events';
};

subtest 'Output::CSV' => sub {
    my $formatter = PerlText::Output::CSV->new;
    my $output = $formatter->format(\@events);

    ok defined $output, 'produces output';
    my @lines = split /\n/, $output;
    ok @lines >= 3, 'has header and data lines';
    like $lines[0], qr/level/, 'header contains level';
    like $lines[0], qr/status/, 'header contains status';
};

subtest 'Output::YAML' => sub {
    my $formatter = PerlText::Output::YAML->new;
    my $output = $formatter->format(\@events);

    ok defined $output, 'produces output';
    like $output, qr/^---/, 'starts with YAML document marker';
    like $output, qr/level:/, 'contains level key';
    like $output, qr/error/, 'contains error value';
};

subtest 'Output::Pretty' => sub {
    my $formatter = PerlText::Output::Pretty->new(color => 0);
    my $output = $formatter->format(\@events);

    ok defined $output, 'produces output';
    like $output, qr/level:/, 'contains level';
    like $output, qr/ERROR/i, 'contains ERROR (uppercased)';
    like $output, qr/message:/, 'contains message';
};

subtest 'Output::Chart with aggregated data' => sub {
    my @agg_data = (
        { ip => '1.1.1.1', count => 100 },
        { ip => '2.2.2.2', count => 50 },
        { ip => '3.3.3.3', count => 25 },
    );

    my $formatter = PerlText::Output::Chart->new(
        value_field => 'count',
        label_field => 'ip',
        color       => 0,
        max_width   => 20,
    );

    my $output = $formatter->format(\@agg_data);

    ok defined $output, 'produces output';
    like $output, qr/1\.1\.1\.1/, 'contains first IP';
    like $output, qr/2\.2\.2\.2/, 'contains second IP';
    like $output, qr/Total:/, 'contains total';
    like $output, qr/175/, 'total is 175';
};

subtest 'Output formatters handle empty input' => sub {
    for my $class (qw(Table JSON CSV YAML Pretty)) {
        my $full_class = "PerlText::Output::$class";
        my $formatter = $full_class->new;
        my $output = $formatter->format([]);
        ok defined $output, "$class handles empty array";
    }
};

subtest 'Output formatters handle hashrefs' => sub {
    my @hashes = (
        { name => 'Alice', score => 95 },
        { name => 'Bob', score => 87 },
    );

    for my $class (qw(Table JSON CSV YAML)) {
        my $full_class = "PerlText::Output::$class";
        my $formatter = $full_class->new;
        my $output = $formatter->format(\@hashes);
        ok defined $output, "$class handles hashrefs";
        like $output, qr/Alice/, "$class contains Alice";
    }
};

done_testing;
