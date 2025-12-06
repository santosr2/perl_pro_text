# Sift

A unified, intelligent log querying and correlation engine for the command line. Think of it as a mini Splunk/Datadog/ELK stack that searches **events**, not files.

## Features

- **Multi-format support**: Auto-detects and parses Nginx, JSON/JSONL, Syslog (BSD & RFC5424)
- **Powerful query language**: SQL-like syntax with filtering, grouping, and aggregations
- **Multi-cloud ready**: AWS CloudWatch, GCP Logging, Azure Monitor, Kubernetes
- **Perl-powered transformations**: Full Perl expressions for custom field manipulation
- **Multiple output formats**: Table, JSON, CSV with syntax highlighting

## Requirements

- Perl 5.36 or later
- [mise](https://mise.jdx.dev/) (recommended) or manual Perl installation

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/perl_pro_text.git
cd perl_pro_text

# Install dependencies
cpanm --installdeps .

# Verify installation
perl -Ilib bin/sift --help
```

## Quick Start

```bash
# Query JSON logs from stdin
echo '{"level":"error","status":500,"message":"Connection failed"}' | sift query 'status >= 500'

# Query nginx access logs
cat /var/log/nginx/access.log | sift query 'status >= 400'

# Filter with AND/OR conditions
cat app.log | sift query 'status >= 500 and service == "auth"'

# Use IN expressions
cat app.log | sift query 'status in {500, 502, 503}'

# Group and aggregate
cat access.log | sift query 'status >= 400 group by ip count'

# Output as JSON
cat app.log | sift query 'level == "error"' --output json
```

## Query Language

### Basic Comparisons

```
field == "value"     # Equality (strings)
field == 200         # Equality (numbers)
field != "value"     # Not equal
field > 100          # Greater than
field >= 100         # Greater than or equal
field < 100          # Less than
field <= 100         # Less than or equal
```

### Logical Operators

```
expr1 and expr2      # Both must be true
expr1 or expr2       # Either must be true
not expr             # Negation
(expr1 or expr2) and expr3  # Grouping with parentheses
```

### IN Expression

```
status in {500, 502, 503}
level in {"error", "critical"}
```

### Aggregations

```
count                # Count matching events
avg field            # Average of numeric field
sum field            # Sum of numeric field
min field            # Minimum value
max field            # Maximum value
```

### Grouping and Sorting

```
group by field       # Group results
group field          # Short form
sort by field asc    # Sort ascending
sort field desc      # Sort descending
limit 10             # Limit results
```

### Full Query Example

```
status >= 400 and method == "POST"
group by ip
count
sort by count desc
limit 10
```

## Supported Log Formats

| Format | Description | Auto-detected |
|--------|-------------|---------------|
| `nginx` | Nginx combined access log and error log | Yes |
| `json` | JSON Lines (JSONL) structured logs | Yes |
| `syslog` | BSD and RFC5424 syslog formats | Yes |

## Cloud Sources

| Source | Provider | Command |
|--------|----------|---------|
| `aws` | AWS CloudWatch Logs | `aws logs` CLI |
| `gcp` | Google Cloud Logging | `gcloud logging` CLI |
| `azure` | Azure Monitor | `az monitor` CLI |
| `k8s` | Kubernetes | `kubectl logs` |

## Commands

```bash
sift query <expression>   # Execute a log query
sift extract              # Extract fields with patterns
sift find                 # Find matching log entries
sift formats              # List supported log formats
sift sources              # List available log sources
```

## Output Formats

- `table` (default) - Colored ASCII table
- `json` - JSON array
- `csv` - CSV format

```bash
sift query 'status >= 500' --output json
sift query 'status >= 500' --output csv
```

## Development

```bash
# Run tests
prove -l -r t/

# Run specific test
prove -l t/unit/query_executor.t

# Check syntax
perl -c -Ilib lib/Sift/Pro.pm
```

## Project Structure

```
perl_pro_text/
├── bin/
│   └── sift                    # CLI entry point
├── lib/
│   └── Sift/
│       ├── Pro.pm             # Main application
│       ├── CLI.pm             # Command-line interface
│       ├── Event.pm           # Unified event class
│       ├── Query/             # Query language (Marpa::R2)
│       ├── Parser/            # Log format parsers
│       ├── Source/            # Log sources (file, cloud)
│       └── Output/            # Output formatters
├── t/                         # Tests
├── cpanfile                   # Dependencies
└── Makefile.PL                # Build configuration
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please ensure:
- All tests pass (`prove -l -r t/`)
- Code follows existing style conventions
- New features include tests

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Marpa::R2](https://metacpan.org/pod/Marpa::R2) - Powerful BNF parser
- [Moo](https://metacpan.org/pod/Moo) - Minimalist Object Orientation
- [Type::Tiny](https://metacpan.org/pod/Type::Tiny) - Type constraints
