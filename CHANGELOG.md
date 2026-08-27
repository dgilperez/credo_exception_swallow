# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-08-27

### Added

- `CredoExceptionSwallow.Checks.Warning.LoggedAndDroppedError` (EX9002): detects
  `{:error, _}` branches that log a warning and then return a success-shaped
  value. `SilentRescue` covers exceptions; this covers the far more common shape
  in idiomatic Elixir, where nothing is ever raised — the batch finishes as
  `{:ok, stats}`, the row is gone, and the only trace is a log line nobody reads.

  The rule is deliberately narrow: only branches that **already log** at
  `warning` or `error` level are considered. Reaching for `Logger.warning` is the
  author saying the failure mattered; a branch that handles the error some other
  way never made that claim and is left alone.

  Covers `case`, `with/else`, `try/else`, `fn`, `receive` and multi-pattern
  clauses (every `Enum.reduce` callback has more than one), guarded clauses, and
  function heads — guarded or not — that pattern-match the failure.

  A branch is accepted when it reports (`ErrorReporter.*`, `Sentry.capture_*`, or
  any configured project-local helper), raises, retries, or propagates:

  - propagation includes returning an error tuple, handing the error back under
    another name (`{:error, r} = err -> ...; err`), a trailing `case`/`if`/`with`
    whose branches propagate, and any returned value that still mentions what the
    error pattern bound (`{count, [reason | errs]}`). An accumulator sitting
    *next* to the error does not count — that is the shape this check exists for.
  - retries include calling the function the branch lives in, and the GenServer
    flavour: `Process.send_after(self(), :connect, delay)`.
  - `propagating_calls` (empty by default) names the project's own doors out,
    such as a Phoenix `send_error(conn, :unprocessable_entity, ...)`.

  Configurable `log_calls`, `reporting_calls` — which accept bare local names, so
  a project whose reporting goes through a private helper can name it —
  `propagating_calls` and `skip_test_files`.

  Known blind spot, documented in the moduledoc: a branch that accumulates the
  failure for the caller to report once per batch is the right pattern and cannot
  be seen one branch at a time. Mark those with
  `# credo:disable-for-next-line`, which turns the false positive into a
  reviewed statement of intent.

  Measured against a 226-file production codebase: 18 candidates, no floods.

### Changed

- the check walks the AST itself instead of using `Credo.Code.prewalk`, so the
  enclosing function name travels down with it. That is what makes retry loops
  recognisable.

## [0.2.1] - 2026-03-19

### Added

- README guidance for function-level rescue support and custom `acceptable_calls`
- test coverage for project-specific error reporter call names

### Changed

- improved Hex package shape by publishing only the relevant source and docs files

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
