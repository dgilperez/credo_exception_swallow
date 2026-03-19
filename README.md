# CredoExceptionSwallow

[![Hex.pm](https://img.shields.io/hexpm/v/credo_exception_swallow.svg)](https://hex.pm/packages/credo_exception_swallow)
[![Hex.pm](https://img.shields.io/hexpm/l/credo_exception_swallow.svg)](https://github.com/dgilperez/credo_exception_swallow/blob/master/LICENSE)
[![Hex.pm](https://img.shields.io/hexpm/dt/credo_exception_swallow.svg)](https://hex.pm/packages/credo_exception_swallow)

A [Credo](https://github.com/rrrene/credo) check to detect silent exception swallowing in Elixir rescue blocks.

Silent exception handling is a dangerous anti-pattern that:
- Hides bugs in production
- Makes debugging extremely difficult
- Creates unpredictable system behavior

This check enforces proper error handling by requiring that every rescue block either logs, reports to error monitoring, or re-raises the exception.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:credo_exception_swallow, "~> 0.2.1", only: [:dev, :test], runtime: false}
  ]
end
```

This package extends Credo with one focused check:

- `CredoExceptionSwallow.Checks.Warning.SilentRescue`

It covers both:

- `try/rescue` blocks
- function-level rescue in `def`/`defp`

## Configuration

Add to your `.credo.exs` in the `checks: %{enabled: [...]}` section:

```elixir
{CredoExceptionSwallow.Checks.Warning.SilentRescue, []}
```

### Options

```elixir
{CredoExceptionSwallow.Checks.Warning.SilentRescue, [
  # Exclude specific files (e.g., health checks)
  files: %{excluded: ["lib/my_app_web/controllers/health_controller.ex"]},
  # Set priority (:high, :normal, :low)
  priority: :high,
  # Skip test files (default: true)
  skip_test_files: true,
  # Additional acceptable function calls beyond defaults
  acceptable_calls: [
    "MyApp.ErrorHandler.report"
  ]
]}
```

### Custom Error Reporters

If your application uses a project-specific reporter facade instead of the default
`ErrorReporter.report_exception/2` naming, add it explicitly:

```elixir
{CredoExceptionSwallow.Checks.Warning.SilentRescue, [
  acceptable_calls: [
    "PhaosCore.ErrorReporter.capture_exception",
    "PhaosCore.ErrorReporter.capture_error"
  ]
]}
```

## What It Detects

### Bad Examples (will trigger warning)

```elixir
# Silent swallow - VERY BAD
try do
  risky_operation()
rescue
  _ -> nil
end

# Silent swallow with specific exception - STILL BAD
try do
  parse_data(input)
rescue
  ArgumentError -> {:error, :invalid}
end
```

### Good Examples (acceptable patterns)

```elixir
# Log the error
try do
  risky_operation()
rescue
  e ->
    Logger.error("Operation failed: #{inspect(e)}")
    {:error, :failed}
end

# Report to error monitoring
try do
  risky_operation()
rescue
  e ->
    Sentry.capture_exception(e, stacktrace: __STACKTRACE__)
    {:error, :failed}
end

# Re-raise (let it crash philosophy)
try do
  risky_operation()
rescue
  e -> reraise e, __STACKTRACE__
end
```

```elixir
# Function-level rescue with reporting
defp load_data(id) do
  Repo.get!(Data, id)
rescue
  error ->
    ErrorReporter.report_exception(error, %{context: "load_data"})
    []
end
```

## Default Acceptable Calls

The following function calls are considered proper error handling:

- `Logger.error/1,2`
- `Logger.warning/1,2`
- `Logger.warn/1,2`
- `Logger.info/1,2`
- `Logger.debug/1,2`
- `ErrorReporter.report_exception/1,2`
- `ErrorReporter.report_message/1,2`
- `Sentry.capture_exception/1,2`
- `Sentry.capture_message/1,2`
- `reraise/2`
- `raise/1,2`

Project-specific reporters can be added through `acceptable_calls`.

## License

MIT License - see [LICENSE](LICENSE) file.
