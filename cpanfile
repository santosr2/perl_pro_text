requires 'perl', '5.036';

# Core Framework
requires 'Moo', '2.005';
requires 'namespace::autoclean', '0.29';
requires 'Type::Tiny', '2.004';
requires 'Path::Tiny', '0.144';
requires 'Log::Any', '1.717';

# CLI
requires 'Getopt::Long::Descriptive', '0.111';
requires 'Term::ANSIColor', '5.01';
requires 'Term::ReadKey', '2.38';

# Query Parser
requires 'Marpa::R2', '12.000';

# Data Parsing
requires 'JSON::MaybeXS', '1.004';
requires 'YAML::XS', '0.88';
requires 'Text::CSV_XS', '1.52';
requires 'DateTime::Format::Strptime', '1.79';
requires 'DateTime::Format::ISO8601', '0.16';

# Output Formatting
requires 'Text::Table::Tiny', '1.03';

# Cloud Integrations
requires 'IPC::Run3', '0.048';

# Testing
on 'test' => sub {
    requires 'Test2::V0', '0.000159';
    requires 'Test2::Tools::Spec', '0.000159';
    requires 'Test::Deep', '1.130';
};

# Development
on 'develop' => sub {
    requires 'Perl::Critic', '1.152';
    requires 'Perl::Tidy', '20231025';
};

# Optional cloud features
feature 'aws', 'AWS CloudWatch integration' => sub {
    requires 'Paws', '0.45';
};
