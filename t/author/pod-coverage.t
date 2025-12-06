#!/usr/bin/env perl
use v5.36;
use Test2::V0;

# Skip unless AUTHOR_TESTING is set
unless ($ENV{AUTHOR_TESTING}) {
    skip_all 'Author tests not required for installation';
}

# Try to load Test::Pod::Coverage
eval { require Test::Pod::Coverage; Test::Pod::Coverage->import() };
if ($@) {
    skip_all 'Test::Pod::Coverage required for this test';
}

# Modules to test for POD coverage
my @modules = qw(
    PerlText::Pro
    PerlText::CLI
    PerlText::Config
    PerlText::Event
    PerlText::Schema
    PerlText::Parser::Base
    PerlText::Parser::Detector
    PerlText::Parser::Nginx
    PerlText::Parser::Apache
    PerlText::Parser::JSON
    PerlText::Parser::Syslog
    PerlText::Query::Parser
    PerlText::Query::AST
    PerlText::Query::Executor
    PerlText::Query::Functions
    PerlText::Transform::Engine
    PerlText::Transform::Eval
    PerlText::Transform::Aggregator
    PerlText::Output::Table
    PerlText::Output::JSON
    PerlText::Output::CSV
    PerlText::Output::YAML
    PerlText::Output::Pretty
    PerlText::Output::Chart
    PerlText::Source::File
    PerlText::Source::Stdin
    PerlText::Source::Follow
    PerlText::Source::Kubernetes
    PerlText::Source::AWS::CloudWatch
    PerlText::Source::GCP::Logging
    PerlText::Source::Azure::Monitor
);

# Private methods that don't need POD
my $trustme = {
    'PerlText::Event' => [qr/^_/],
    'PerlText::CLI'   => [qr/^_/, qr/^cmd_/],
    'PerlText::Parser::Nginx'   => [qr/^_/],
    'PerlText::Parser::Apache'  => [qr/^_/],
    'PerlText::Parser::JSON'    => [qr/^_/],
    'PerlText::Parser::Syslog'  => [qr/^_/],
    'PerlText::Query::Parser'   => [qr/^_/],
    'PerlText::Query::Executor' => [qr/^_/],
    'PerlText::Transform::Eval' => [qr/^_/],
    'PerlText::Output::Chart'   => [qr/^_/],
    'PerlText::Config'          => [qr/^_/],
    'PerlText::Source::Follow'  => [qr/^_/],
};

for my $module (@modules) {
    my $params = {};
    if (exists $trustme->{$module}) {
        $params->{trustme} = $trustme->{$module};
    }

    subtest "POD coverage for $module" => sub {
        eval { require_ok($module) };
        if ($@) {
            skip_all "Cannot load $module: $@";
            return;
        }

        pod_coverage_ok($module, $params, "POD coverage for $module");
    };
}

done_testing;
