defmodule CredoExceptionSwallow.Checks.Warning.SilentRescue do
  @moduledoc ~S"""
  Detects rescue blocks that silently swallow exceptions without logging or reporting.

  Silent exception handling is dangerous because:
  1. Bugs go unnoticed in production
  2. Debugging becomes extremely difficult
  3. System behavior becomes unpredictable

  ## Bad Examples

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

  ## Good Examples

      # Report to error monitoring (Sentry/ErrorReporter)
      try do
        risky_operation()
      rescue
        e ->
          ErrorReporter.report_exception(e, __STACKTRACE__)
          {:error, :failed}
      end

      # Log the error
      try do
        risky_operation()
      rescue
        e ->
          Logger.error("Operation failed: #{inspect(e)}")
          {:error, :failed}
      end

      # Re-raise (let it crash philosophy)
      try do
        risky_operation()
      rescue
        e -> reraise e, __STACKTRACE__
      end

  ## Acceptable Patterns (won't trigger warning)

  - rescue blocks that call `Logger` functions
  - rescue blocks that call `ErrorReporter` or `Sentry`
  - rescue blocks that use `reraise` or `raise`
  - rescue blocks in test files (configurable)

  ## Configuration

      # In .credo.exs
      {CredoExceptionSwallow.Checks.Warning.SilentRescue, [
        # Exclude specific files (e.g., health checks)
        files: %{excluded: ["lib/my_app_web/controllers/health_controller.ex"]},
        # Set priority (:high, :normal, :low)
        priority: :high,
        # Skip test files (default: true)
        skip_test_files: true,
        # Additional acceptable function calls
        acceptable_calls: [
          "MyApp.ErrorHandler.report"
        ]
      ]}
  """

  use Credo.Check,
    id: "EX9001",
    base_priority: :high,
    category: :warning,
    exit_status: 2,
    param_defaults: [
      skip_test_files: true,
      # Functions that indicate proper error handling
      acceptable_calls: [
        "Logger.error",
        "Logger.warning",
        "Logger.warn",
        "Logger.info",
        "Logger.debug",
        "ErrorReporter.report_exception",
        "ErrorReporter.report_message",
        "Sentry.capture_exception",
        "Sentry.capture_message",
        "reraise",
        "raise"
      ]
    ],
    explanations: [
      check: """
      Rescue blocks should not silently swallow exceptions. Every caught exception
      should be either:

      1. Logged (using Logger)
      2. Reported to error monitoring (Sentry/ErrorReporter)
      3. Re-raised (using reraise)

      Silent exception handling hides bugs and makes debugging nearly impossible.
      This check enforces a zero-tolerance policy for exception swallowing.
      """,
      params: [
        skip_test_files: "Whether to skip test files (default: true)",
        acceptable_calls: "List of function calls that indicate proper error handling"
      ]
    ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    acceptable_calls = Params.get(params, :acceptable_calls, __MODULE__)
    skip_test_files = Params.get(params, :skip_test_files, __MODULE__)

    # Skip test files if configured
    if skip_test_files && test_file?(source_file.filename) do
      []
    else
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, acceptable_calls))
    end
  end

  defp test_file?(filename) do
    String.contains?(filename, "test/") ||
      String.contains?(filename, "_test.exs") ||
      String.ends_with?(filename, "_test.ex")
  end

  # Match try blocks with rescue clauses
  # AST structure: {:try, meta, [[do: ..., rescue: [clauses]]]}
  defp traverse({:try, _meta, [keywords]} = ast, issues, issue_meta, acceptable_calls)
       when is_list(keywords) do
    rescue_clauses = Keyword.get(keywords, :rescue, [])

    new_issues =
      rescue_clauses
      |> Enum.flat_map(fn clause ->
        check_rescue_clause(clause, issue_meta, acceptable_calls)
      end)

    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta, _acceptable_calls) do
    {ast, issues}
  end

  defp check_rescue_clause({:->, meta, [_pattern, body]}, issue_meta, acceptable_calls) do
    if has_acceptable_call?(body, acceptable_calls) do
      []
    else
      line_no = meta[:line] || 0

      [
        format_issue(
          issue_meta,
          message:
            "Rescue block silently swallows exception without logging or error reporting. " <>
              "Add Logger.error/warning or ErrorReporter.report_exception.",
          line_no: line_no
        )
      ]
    end
  end

  defp check_rescue_clause(_clause, _issue_meta, _acceptable_calls), do: []

  defp has_acceptable_call?(body, acceptable_calls) do
    Macro.prewalk(body, false, fn
      # Check for function calls like Module.function()
      {{:., _, [{:__aliases__, _, module_parts}, func_name]}, _, _args}, _acc ->
        full_name = Enum.join(module_parts, ".") <> ".#{func_name}"

        if full_name in acceptable_calls do
          {nil, true}
        else
          {nil, false}
        end

      # Check for reraise
      {:reraise, _, _}, _acc ->
        {nil, true}

      # Check for raise (re-raising)
      {:raise, _, _}, _acc ->
        {nil, true}

      # Check for Logger calls (atoms)
      {{:., _, [{:__aliases__, _, [:Logger]}, func]}, _, _}, _acc
      when func in [:error, :warning, :warn, :info, :debug] ->
        {nil, true}

      # Check for ErrorReporter calls
      {{:., _, [{:__aliases__, _, [:ErrorReporter]}, _func]}, _, _}, _acc ->
        {nil, true}

      # Check for Sentry calls
      {{:., _, [{:__aliases__, _, [:Sentry]}, _func]}, _, _}, _acc ->
        {nil, true}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
  end
end
