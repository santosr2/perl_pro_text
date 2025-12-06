use v5.36;
use Test2::V0;
use Sift::Parser::Syslog;

my $parser = Sift::Parser::Syslog->new;

subtest 'format detection' => sub {
    ok $parser->can_parse('Dec  4 10:00:00 myhost sshd[1234]: Connection from 1.2.3.4'), 'detects BSD format';
    ok $parser->can_parse('<134>1 2025-12-04T10:00:00Z host app 1234 - - Message'), 'detects RFC5424 format';
    ok !$parser->can_parse('just some random text'), 'rejects non-syslog';
    ok !$parser->can_parse('{"json": "data"}'), 'rejects JSON';
};

subtest 'parse BSD syslog' => sub {
    my $line = 'Dec  4 10:00:00 myhost sshd[1234]: Connection from 192.168.1.1';
    my $event = $parser->parse($line);

    ok defined $event, 'parsed successfully';
    is $event->get('hostname'), 'myhost', 'hostname extracted';
    is $event->get('program'), 'sshd', 'program extracted';
    is $event->get('pid'), 1234, 'pid extracted';
    is $event->get('message'), 'Connection from 192.168.1.1', 'message extracted';
    is $event->get('format'), 'bsd', 'format is bsd';
};

subtest 'parse BSD syslog without PID' => sub {
    my $line = 'Dec  4 10:00:00 myhost kernel: CPU0 temperature above threshold';
    my $event = $parser->parse($line);

    ok defined $event, 'parsed successfully';
    is $event->get('hostname'), 'myhost', 'hostname extracted';
    is $event->get('program'), 'kernel', 'program extracted';
    ok !defined $event->get('pid'), 'no pid';
    like $event->get('message'), qr/CPU0 temperature/, 'message extracted';
};

subtest 'parse RFC5424 syslog' => sub {
    my $line = '<134>1 2025-12-04T10:00:00Z myhost myapp 1234 ID47 - Application started';
    my $event = $parser->parse($line);

    ok defined $event, 'parsed successfully';
    is $event->get('hostname'), 'myhost', 'hostname extracted';
    is $event->get('appname'), 'myapp', 'appname extracted';
    is $event->get('procid'), '1234', 'procid extracted';
    is $event->get('msgid'), 'ID47', 'msgid extracted';
    is $event->get('message'), 'Application started', 'message extracted';
    is $event->get('format'), 'rfc5424', 'format is rfc5424';
    is $event->get('priority'), 134, 'priority extracted';
    is $event->get('facility'), 'local0', 'facility decoded';
    is $event->get('severity'), 'info', 'severity decoded';
};

subtest 'parse RFC5424 with structured data' => sub {
    my $line = '<165>1 2025-12-04T10:00:00Z host app - - [exampleSDID@32473 iut="3" eventSource="Application"] Test message';
    my $event = $parser->parse($line);

    ok defined $event, 'parsed successfully';
    ok defined $event->get('structured_data'), 'structured data preserved';
    like $event->get('structured_data'), qr/exampleSDID/, 'SD content present';
};

subtest 'severity levels' => sub {
    # Priority = facility * 8 + severity
    # facility 16 (local0) + severity 3 (err) = 131
    my $line = '<131>1 2025-12-04T10:00:00Z host app - - - Error occurred';
    my $event = $parser->parse($line);

    is $event->get('severity'), 'err', 'error severity decoded';

    # facility 16 (local0) + severity 0 (emerg) = 128
    $line = '<128>1 2025-12-04T10:00:00Z host app - - - Emergency!';
    $event = $parser->parse($line);
    is $event->get('severity'), 'emerg', 'emergency severity decoded';
};

done_testing;
