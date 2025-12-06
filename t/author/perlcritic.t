#!/usr/bin/env perl
use v5.36;
use Test2::V0;
use Path::Tiny;

# Skip unless AUTHOR_TESTING is set
unless ($ENV{AUTHOR_TESTING}) {
    skip_all 'Author tests not required for installation';
}

# Try to load Test::Perl::Critic
eval { require Test::Perl::Critic };
if ($@) {
    skip_all 'Test::Perl::Critic required for this test';
}

# Configure critic
my $rcfile = path('.perlcriticrc');
if ($rcfile->exists) {
    Test::Perl::Critic->import(-profile => $rcfile->stringify);
} else {
    Test::Perl::Critic->import(-severity => 3);
}

# Test all modules in lib/
all_critic_ok('lib');

done_testing;
