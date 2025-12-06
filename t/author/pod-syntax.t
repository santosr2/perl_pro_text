#!/usr/bin/env perl
use v5.36;
use Test2::V0;
use Path::Tiny;

# Skip unless AUTHOR_TESTING is set
unless ($ENV{AUTHOR_TESTING}) {
    skip_all 'Author tests not required for installation';
}

# Try to load Test::Pod
eval { require Test::Pod; Test::Pod->import() };
if ($@) {
    skip_all 'Test::Pod required for this test';
}

# Find all .pm files in lib/
my $lib = path('lib');
my @pm_files = $lib->children(qr/\.pm$/);

# Recursively find all .pm files
my @all_pm;
my $iter = $lib->iterator({ recurse => 1 });
while (my $file = $iter->()) {
    push @all_pm, $file if $file =~ /\.pm$/;
}

for my $file (@all_pm) {
    pod_file_ok($file->stringify, "POD syntax in $file");
}

done_testing;
