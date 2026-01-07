# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-07

### Added

- Initial release
- `CredoExceptionSwallow.Checks.Warning.SilentRescue` check to detect rescue blocks that silently swallow exceptions
- Detects rescue blocks without proper logging, error reporting, or re-raising
- Configurable acceptable function calls (Logger, Sentry, ErrorReporter, reraise, raise)
- Option to skip test files (enabled by default)
- File exclusion support via Credo's standard `files` option
