# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-03-12

### Fixed

- **Function-level rescue detection**: Now detects silent rescue in `def`/`defp` blocks (e.g., `defp foo do ... rescue _ -> [] end`), not just `try/rescue`. Previously, function-level rescues were invisible to the check.
- **Accumulator bug in `has_acceptable_call?`**: `Macro.prewalk` accumulator was reset to `false` on non-matching AST nodes, potentially missing acceptable calls found earlier in sibling branches.

### Changed

- Expanded test suite from 5 to 20+ tests covering function-level rescue, accumulator correctness, mixed scenarios, and test file skipping.

## [0.1.0] - 2025-01-07

### Added

- Initial release
- `CredoExceptionSwallow.Checks.Warning.SilentRescue` check to detect rescue blocks that silently swallow exceptions
- Detects rescue blocks without proper logging, error reporting, or re-raising
- Configurable acceptable function calls (Logger, Sentry, ErrorReporter, reraise, raise)
- Option to skip test files (enabled by default)
- File exclusion support via Credo's standard `files` option
