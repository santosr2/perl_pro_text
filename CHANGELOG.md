# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial project structure with modern Perl 5.36 features
- Core `PerlText::Event` class for unified log representation
- Query language parser using Marpa::R2 with BNF grammar
- Query executor with support for:
  - Comparison operators: `==`, `!=`, `>`, `>=`, `<`, `<=`
  - Logical operators: `and`, `or`, `not`
  - `IN` expressions: `field in {value1, value2}`
  - Grouping with `group by`
  - Aggregations: `count`, `avg`, `sum`, `min`, `max`
  - Sorting with `sort by field asc/desc`
  - Result limiting with `limit N`
- Log format parsers:
  - Nginx combined access log and error log
  - JSON/JSONL structured logs
  - Syslog (BSD and RFC5424 formats)
- Auto-detection of log formats
- Output formatters:
  - ASCII table with color highlighting
  - JSON
  - CSV
- Cloud source integrations (structure):
  - AWS CloudWatch Logs
  - GCP Cloud Logging
  - Azure Monitor
  - Kubernetes (kubectl logs)
- CLI tool `ptx` with commands:
  - `query` - Execute log queries
  - `formats` - List supported formats
  - `sources` - List available sources
- Comprehensive test suite using Test2::V0
