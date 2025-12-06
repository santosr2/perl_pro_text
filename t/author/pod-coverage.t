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
    Sift::Pro
    Sift::CLI
    Sift::Config
    Sift::Event
    Sift::Schema
    Sift::Parser::Base
    Sift::Parser::Detector
    Sift::Parser::Nginx
    Sift::Parser::Apache
    Sift::Parser::JSON
    Sift::Parser::Syslog
    Sift::Query::Parser
    Sift::Query::AST
    Sift::Query::Executor
    Sift::Query::Functions
    Sift::Transform::Engine
    Sift::Transform::Eval
    Sift::Transform::Aggregator
    Sift::Output::Table
    Sift::Output::JSON
    Sift::Output::CSV
    Sift::Output::YAML
    Sift::Output::Pretty
    Sift::Output::Chart
    Sift::Source::File
    Sift::Source::Stdin
    Sift::Source::Follow
    Sift::Source::Kubernetes
    Sift::Source::AWS::CloudWatch
    Sift::Source::GCP::Logging
    Sift::Source::Azure::Monitor
);

# Private methods that don't need POD
my $trustme = {
    'Sift::Event' => [qr/^_/],
    'Sift::CLI'   => [qr/^_/, qr/^cmd_/],
    'Sift::Parser::Nginx'   => [qr/^_/],
    'Sift::Parser::Apache'  => [qr/^_/],
    'Sift::Parser::JSON'    => [qr/^_/],
    'Sift::Parser::Syslog'  => [qr/^_/],
    'Sift::Query::Parser'   => [qr/^_/],
    'Sift::Query::Executor' => [qr/^_/],
    'Sift::Transform::Eval' => [qr/^_/],
    'Sift::Output::Chart'   => [qr/^_/],
    'Sift::Config'          => [qr/^_/],
    'Sift::Source::Follow'  => [qr/^_/],
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
