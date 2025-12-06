use v5.36;
use Test2::V0;
use Path::Tiny;
use Sift::Source::File;

my $fixtures_dir = path(__FILE__)->parent->parent->child('fixtures');

subtest 'Source::File single file' => sub {
    my $source = Sift::Source::File->new(
        path => $fixtures_dir->child('nginx_access.log')->stringify,
    );

    is $source->source_type, 'file', 'source type is file';

    my $events = $source->fetch_events;
    ok ref $events eq 'ARRAY', 'returns arrayref';
    ok @$events > 0, 'found events';

    my $first = $events->[0];
    ok defined $first->get('status'), 'event has status field';
    ok defined $first->get('method'), 'event has method field';
};

subtest 'Source::File with limit' => sub {
    my $source = Sift::Source::File->new(
        path => $fixtures_dir->child('nginx_access.log')->stringify,
    );

    my $events = $source->fetch_events(limit => 2);
    is scalar(@$events), 2, 'respects limit';
};

subtest 'Source::File nonexistent file' => sub {
    my $source = Sift::Source::File->new(
        path => '/nonexistent/path/file.log',
    );

    my $events = $source->fetch_events;
    is scalar(@$events), 0, 'returns empty for nonexistent file';
};

subtest 'Source::File glob pattern' => sub {
    skip_all 'glob test requires multiple files' unless -d $fixtures_dir;

    my $source = Sift::Source::File->new(
        path => $fixtures_dir->child('*.log')->stringify,
    );

    my $paths = $source->paths;
    ok ref $paths eq 'ARRAY', 'paths is arrayref';
    ok @$paths >= 1, 'found at least one file';
};

subtest 'Source::File JSON logs' => sub {
    my $source = Sift::Source::File->new(
        path => $fixtures_dir->child('json_logs.jsonl')->stringify,
    );

    my $events = $source->fetch_events;
    ok @$events > 0, 'parsed JSON logs';

    my $first = $events->[0];
    ok defined $first->get('level'), 'has level field';
};

done_testing;
