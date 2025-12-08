use v5.36;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Sift',
    VERSION_FROM     => 'lib/Sift/CLI.pm',
    ABSTRACT         => 'Log query and analysis engine - sift through your logs',
    AUTHOR           => 'Sift Contributors',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.036',

    EXE_FILES => ['bin/sift'],

    PREREQ_PM => {
        'Moo'                        => '2.005',
        'namespace::autoclean'       => '0.29',
        'Type::Tiny'                 => '2.004',
        'Path::Tiny'                 => '0.144',
        'Log::Any'                   => '1.717',
        'Getopt::Long::Descriptive'  => '0.111',
        'Term::ANSIColor'            => '5.01',
        'Marpa::R2'                  => '12.000',
        'JSON::MaybeXS'              => '1.004',
        'YAML::XS'                   => '0.88',
        'Text::CSV_XS'               => '1.52',
        'DateTime::Format::Strptime' => '1.79',
        'Text::Table::Tiny'          => '1.03',
        'IPC::Run3'                  => '0.048',
    },

    TEST_REQUIRES => {
        'Test2::V0'    => '0.000159',
        'Test::Deep'   => '1.130',
    },

    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/santosr2/sift.git',
                web  => 'https://github.com/santosr2/sift',
            },
        },
    },
);
