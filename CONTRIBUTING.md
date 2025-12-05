# Contributing to PerlText Pro

Thank you for your interest in contributing to PerlText Pro! This document provides guidelines and information for contributors.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you are expected to uphold this code.

## How to Contribute

### Reporting Bugs

Before creating a bug report, please check existing issues to avoid duplicates. When creating a bug report, include:

- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs actual behavior
- Sample log data (anonymized if necessary)
- Perl version (`perl -v`)
- Operating system and version

### Suggesting Features

Feature requests are welcome! Please provide:

- A clear description of the feature
- Use cases and examples
- Any relevant log format samples

### Pull Requests

1. Fork the repository
2. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. Make your changes
4. Add or update tests as needed
5. Ensure all tests pass:
   ```bash
   prove -l -r t/
   ```
6. Commit with a descriptive message
7. Push to your fork and open a Pull Request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/perl_pro_text.git
cd perl_pro_text

# Install dependencies
cpanm --installdeps .

# Run tests
prove -l -r t/

# Test the CLI
perl -Ilib bin/ptx --help
```

## Coding Standards

### Perl Version

This project requires **Perl 5.36** or later. Use modern Perl features:

```perl
use v5.36;  # Enables strict, warnings, signatures, say
```

### Style Guidelines

- Use **Moo** for object-oriented code
- Use **subroutine signatures** (not `@_` unpacking)
- Use **Type::Tiny** for type constraints
- Use **Path::Tiny** for file operations
- Use **4-space indentation** (no tabs)
- Keep lines under **100 characters** when practical

### Example Code Style

```perl
package PerlText::Example;
use v5.36;
use Moo;
use Types::Standard qw(Str Int);
use namespace::autoclean;

has name => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has count => (
    is      => 'ro',
    isa     => Int,
    default => 0,
);

sub process ($self, $input) {
    # Implementation
    return $result;
}

1;
```

### Testing

- Write tests using **Test2::V0**
- Place unit tests in `t/unit/`
- Place integration tests in `t/integration/`
- Use descriptive test names

```perl
use Test2::V0;
use PerlText::Example;

subtest 'process handles empty input' => sub {
    my $obj = PerlText::Example->new(name => 'test');
    my $result = $obj->process('');
    is $result, undef, 'returns undef for empty input';
};

done_testing;
```

## Project Structure

```
lib/PerlText/
├── Pro.pm              # Main application class
├── CLI.pm              # Command-line interface
├── Event.pm            # Unified log event
├── Query/
│   ├── Grammar.pm      # Marpa::R2 BNF grammar
│   ├── Parser.pm       # Query string parser
│   ├── AST.pm          # Abstract syntax tree nodes
│   └── Executor.pm     # Query execution engine
├── Parser/
│   ├── Base.pm         # Parser role/interface
│   ├── Detector.pm     # Format auto-detection
│   ├── Nginx.pm        # Nginx log parser
│   ├── JSON.pm         # JSON/JSONL parser
│   └── Syslog.pm       # Syslog parser
├── Source/
│   ├── Base.pm         # Source role/interface
│   ├── File.pm         # Local file source
│   └── Kubernetes.pm   # kubectl logs source
└── Output/
    ├── Base.pm         # Output role/interface
    ├── Table.pm        # ASCII table formatter
    ├── JSON.pm         # JSON formatter
    └── CSV.pm          # CSV formatter
```

## Adding a New Log Parser

1. Create a new module in `lib/PerlText/Parser/`:

```perl
package PerlText::Parser::MyFormat;
use v5.36;
use Moo;
use PerlText::Event;
use namespace::autoclean;

with 'PerlText::Parser::Base';

has '+source_name' => (default => 'myformat');

sub format_name ($self) { 'myformat' }

sub can_parse ($self, $line) {
    # Return 1 if this parser can handle the line
    return $line =~ /some_pattern/ ? 1 : 0;
}

sub parse ($self, $line, $source = undef) {
    $source //= $self->source_name;

    # Parse the line and extract fields
    my %fields = (...);

    return PerlText::Event->new(
        timestamp => time(),
        source    => $source,
        raw       => $line,
        fields    => \%fields,
    );
}

1;
```

2. Register in `lib/PerlText/Parser/Detector.pm`
3. Add tests in `t/unit/parsers/myformat.t`
4. Add sample data in `t/fixtures/`

## Adding a New Cloud Source

1. Create a new module in `lib/PerlText/Source/`
2. Implement the source interface (iterator pattern)
3. Use CLI tools (`aws`, `gcloud`, `az`, `kubectl`) via `IPC::Run3`
4. Add tests and documentation

## Questions?

Feel free to open an issue for any questions about contributing.
