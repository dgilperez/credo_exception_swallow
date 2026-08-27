defmodule CredoExceptionSwallow.Checks.Warning.LoggedAndDroppedError do
  @moduledoc ~S"""
  Detects error branches that write a warning to the log and then carry on as if
  nothing had happened.

  `SilentRescue` covers exceptions. This check covers the far more common shape
  in idiomatic Elixir: an `{:error, reason}` clause that never raises anything.
  The code notices the failure, logs it, and returns a value that lets the caller
  report success.

  The rule is deliberately narrow: **only branches that already log at
  `warning` or `error` level are considered.** If the author reached for
  `Logger.warning`, they judged the failure worth writing down — and a log line
  nobody reads is not a report. A branch that handles the error some other way
  (rendering it, returning a default) is not flagged, because it never claimed
  the failure mattered.

  A branch is accepted when it does any of:

  1. reports to error monitoring (`ErrorReporter.*`, `Sentry.capture_*`)
  2. raises or re-raises
  3. propagates the failure — its return value is an error tuple, `:error`, or
     anything that still mentions what the error pattern bound
  4. retries — it calls the function it lives in, or posts itself a message
  5. calls one of the project's own `propagating_calls`

  ## Bad Examples

      # The run finishes as {:ok, stats} and the row is gone.
      case upsert(row) do
        {:ok, _} -> bump(acc, :rows_created)
        {:error, reason} ->
          Logger.warning("upsert failed: #{inspect(reason)}")
          bump(acc, nil)
      end

      # Function-head flavour of the same thing.
      defp reduce({:error, reason, _meta}, acc) do
        Logger.warning("mapping failed: #{inspect(reason)}")
        acc
      end

  ## Good Examples

      # Propagates: the caller still learns about it.
      {:error, reason} ->
        Logger.warning("upsert failed: #{inspect(reason)}")
        {:error, reason}

      # Reports: somebody finds out even though the run continues.
      {:error, reason} ->
        ErrorReporter.report_message("upsert failed", %{reason: inspect(reason)})
        bump(acc, nil)

      # Not flagged: no warning-level log, so no claim that it mattered.
      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}

  ## Known blind spot

  A branch that pushes the failure onto an accumulator which the *caller*
  reports once per batch is the right pattern, and this check cannot see it:
  it only reads one branch at a time. Mark those with Credo's own escape
  hatch, which turns the false positive into a reviewed statement of intent:

      # credo:disable-for-next-line CredoExceptionSwallow.Checks.Warning.LoggedAndDroppedError
      {:error, reason} ->
        Logger.warning("...")
        [location.key | failures]   # reported per run by the caller

  ## A note on volume

  Reporting per dropped row is how monitoring quotas die. Aggregate per batch or
  per run and report once — this check only asks that *somebody* finds out, not
  that every row gets its own event.

  ## Configuration

      # In .credo.exs
      {CredoExceptionSwallow.Checks.Warning.LoggedAndDroppedError, [
        # Only these files (e.g. syncs and workers, where dropped rows hurt most)
        files: %{included: ["lib/**/sync/**", "lib/**/workers/**"]},
        # Log calls that count as "the author said this matters"
        log_calls: ["Logger.warning", "Logger.error"],
        # Calls that count as reporting
        reporting_calls: ["ErrorReporter.report_message", "Sentry.capture_message"],
        # Calls that hand the failure on without monitoring (e.g. an HTTP error
        # response). Empty by default.
        propagating_calls: ["send_error"],
        # Skip test files (default: true)
        skip_test_files: true
      ]}
  """

  use Credo.Check,
    id: "EX9002",
    base_priority: :high,
    category: :warning,
    exit_status: 2,
    param_defaults: [
      skip_test_files: true,
      # Levels that mean "the author judged this failure worth recording".
      # :info and :debug are absent on purpose — they are not failure signals.
      log_calls: [
        "Logger.warning",
        "Logger.warn",
        "Logger.error"
      ],
      # Calls that hand the failure to somebody else without going through error
      # monitoring — a Phoenix `send_error(conn, :unprocessable_entity, ...)`,
      # for instance. Empty by default: naming them is a per-project decision.
      propagating_calls: [],
      # Calls that mean somebody outside the log will find out.
      reporting_calls: [
        "ErrorReporter.report",
        "ErrorReporter.report_message",
        "ErrorReporter.report_warning",
        "ErrorReporter.report_exception",
        "Sentry.capture_exception",
        "Sentry.capture_message",
        "Appsignal.send_error",
        "Honeybadger.notify",
        "Rollbax.report"
      ]
    ],
    explanations: [
      check: """
      An error branch that logs a warning and then returns a value indistinguishable
      from success makes the failure invisible: the batch reports `{:ok, stats}`, the
      row is gone, and the only trace is a log line nobody reads.

      Either report it, raise, or propagate the error to the caller.
      """,
      params: [
        skip_test_files: "Whether to skip test files (default: true)",
        log_calls: "Log calls that mark the branch as a failure worth recording",
        propagating_calls: "Calls that hand the failure on without error monitoring",
        reporting_calls: "Calls that count as reporting the failure"
      ]
    ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    opts = %{
      log_calls: Params.get(params, :log_calls, __MODULE__),
      propagating_calls: Params.get(params, :propagating_calls, __MODULE__),
      reporting_calls: Params.get(params, :reporting_calls, __MODULE__)
    }

    if Params.get(params, :skip_test_files, __MODULE__) && test_file?(source_file.filename) do
      []
    else
      source_file
      |> SourceFile.ast()
      |> walk(issue_meta, Map.put(opts, :current_function, nil))
    end
  end

  defp test_file?(filename) do
    String.contains?(filename, "test/") ||
      String.contains?(filename, "_test.exs") ||
      String.ends_with?(filename, "_test.ex")
  end

  # A hand-rolled walk instead of `Credo.Code.prewalk` so the enclosing function
  # name travels down with the AST: a branch whose return value calls the
  # function it lives in is a retry, not a dropped failure, and retry loops are
  # far too common in Elixir to flag.
  defp walk({def_type, meta, [head, keywords]}, issue_meta, opts)
       when def_type in [:def, :defp] and is_list(keywords) do
    opts = Map.put(opts, :current_function, head_name(head))
    body = Keyword.get(keywords, :do)
    args = head_args(head)

    head_issues =
      if body && Enum.any?(Enum.map(args, &strip_guard/1), &error_pattern?/1) do
        check_branch(args, body, meta, issue_meta, opts)
      else
        []
      end

    head_issues ++ walk(keywords, issue_meta, opts)
  end

  # `->` clauses cover case, with/else, try/else, fn and receive in one shot.
  # `patterns` is a list because `fn {:error, r}, acc -> ... end` — the shape of
  # every `Enum.reduce` callback — carries more than one.
  defp walk({:->, meta, [patterns, body]}, issue_meta, opts) when is_list(patterns) do
    check_branch(patterns, body, meta, issue_meta, opts) ++ walk(body, issue_meta, opts)
  end

  defp walk({form, _meta, args}, issue_meta, opts) when is_list(args) do
    walk(form, issue_meta, opts) ++ walk(args, issue_meta, opts)
  end

  defp walk({left, right}, issue_meta, opts) do
    walk(left, issue_meta, opts) ++ walk(right, issue_meta, opts)
  end

  defp walk(list, issue_meta, opts) when is_list(list),
    do: Enum.flat_map(list, &walk(&1, issue_meta, opts))

  defp walk(_ast, _issue_meta, _opts), do: []

  defp check_branch(patterns, body, meta, issue_meta, opts) do
    # Only names bound by the failure itself count. An accumulator sitting next
    # to it (`fn {:error, r}, acc -> ... acc end`) is not the failure travelling
    # onwards — that is precisely the shape this check exists to catch.
    error_patterns = patterns |> Enum.map(&strip_guard/1) |> Enum.filter(&error_pattern?/1)
    opts = Map.put(opts, :bound_names, Enum.flat_map(error_patterns, &bound_names/1))

    if error_patterns != [] && logs_failure?(body, opts) && dropped?(body, opts) do
      [
        format_issue(
          issue_meta,
          message:
            "This error is logged and then dropped: the caller cannot tell it happened. " <>
              "Report it (ErrorReporter/Sentry), raise, or return the error to the caller.",
          line_no: meta[:line] || 0
        )
      ]
    else
      []
    end
  end

  defp head_name({:when, _meta, [head | _guards]}), do: head_name(head)
  defp head_name({name, _meta, _args}) when is_atom(name), do: name
  defp head_name(_head), do: nil

  # `defp reduce({:error, r}, acc) when is_map(acc)` wraps the head in `:when`.
  defp head_args({:when, _meta, [head | _guards]}), do: head_args(head)
  defp head_args({_name, _meta, args}) when is_list(args), do: args
  defp head_args(_head), do: []

  # A guarded clause is `{:when, _, [pattern, guard]}`; the pattern is inside.
  defp strip_guard({:when, _meta, [pattern | _guards]}), do: pattern
  defp strip_guard(pattern), do: pattern

  defp error_pattern?(:error), do: true
  defp error_pattern?({:error, _reason}), do: true
  defp error_pattern?({:{}, _meta, [:error | _rest]}), do: true
  # `{:error, reason} = err` and `err = {:error, reason}`
  defp error_pattern?({:=, _meta, [left, right]}),
    do: error_pattern?(left) || error_pattern?(right)

  defp error_pattern?(_pattern), do: false

  defp logs_failure?(body, %{log_calls: log_calls}), do: calls_any?(body, log_calls)

  # Dropped means: nobody outside this branch finds out. Not reported, not
  # raised, and the value handed back does not carry the failure.
  defp dropped?(body, %{reporting_calls: reporting_calls} = opts) do
    not (calls_any?(body, reporting_calls) or raises?(body) or propagates_error?(body, opts) or
           retries?(body, opts) or hands_off?(body, opts))
  end

  # The failure leaves through a door this check does not know about — a Phoenix
  # error response, a message to the caller. Which calls those are is a
  # per-project decision, so the list starts empty.
  defp hands_off?(_body, %{propagating_calls: []}), do: false

  defp hands_off?(body, %{propagating_calls: calls}),
    do: body |> last_expression() |> calls_any?(calls)

  # `{:error, %TransportError{}} -> Logger.warning(...); fetch(url, retries - 1)`
  # is a retry loop: the operation carries on, so nothing has been dropped yet.
  defp retries?(_body, %{current_function: nil}), do: false

  defp retries?(body, %{current_function: name}) do
    case last_expression(body) do
      {^name, _meta, args} when is_list(args) -> true
      _ -> reschedules_itself?(body)
    end
  end

  # The GenServer flavour of a retry: log, then post yourself a message to try
  # again later. `Process.send_after(self(), :connect, delay)`.
  defp reschedules_itself?(body) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {{:., _meta, [{:__aliases__, _am, [:Process]}, :send_after]}, _cm, args} = ast, acc ->
          {ast, acc or sends_to_self?(args)}

        {:send, _meta, args} = ast, acc ->
          {ast, acc or sends_to_self?(args)}

        ast, acc ->
          {ast, acc}
      end)

    found
  end

  defp sends_to_self?([{:self, _meta, _args} | _rest]), do: true
  defp sends_to_self?(_args), do: false

  defp propagates_error?(body, opts) do
    last = last_expression(body)
    error_value?(last, opts) or returns_bound_error?(last, opts)
  end

  # The failure travels onwards if the returned value mentions anything the
  # error pattern bound: `err`, `{:error, reason}`, `[{id, reason} | acc]`.
  # Following the binding keeps the check from crying wolf on the most common
  # propagation shapes there are.
  defp returns_bound_error?(expression, %{bound_names: []}) when not is_nil(expression), do: false

  defp returns_bound_error?(expression, %{bound_names: names}) do
    {_ast, found} =
      Macro.prewalk(expression, false, fn
        {name, _meta, context} = ast, acc when is_atom(name) and is_atom(context) ->
          if name in names, do: {ast, true}, else: {ast, acc}

        ast, acc ->
          {ast, acc}
      end)

    found
  end

  # Every variable the clause pattern binds. `{:error, reason} = err` binds both
  # `reason` and `err`, and either one showing up in the returned value means the
  # failure travels onwards instead of being dropped.
  defp bound_names({name, _meta, context}) when is_atom(name) and is_atom(context), do: [name]

  defp bound_names({left, right}), do: bound_names(left) ++ bound_names(right)

  defp bound_names({_form, _meta, args}) when is_list(args),
    do: Enum.flat_map(args, &bound_names/1)

  defp bound_names(list) when is_list(list), do: Enum.flat_map(list, &bound_names/1)
  defp bound_names(_pattern), do: []

  defp last_expression({:__block__, _meta, []}), do: nil
  defp last_expression({:__block__, _meta, statements}), do: List.last(statements)
  defp last_expression(expression), do: expression

  defp error_value?(:error, _opts), do: true
  defp error_value?({:error, _reason}, _opts), do: true
  defp error_value?({:{}, _meta, [:error | _rest]}, _opts), do: true

  # A trailing `case`/`if`/`with` propagates if any of its branches does. Being
  # generous here is deliberate: this check must not cry wolf.
  defp error_value?({:case, _meta, [_subject, keywords]}, opts) when is_list(keywords),
    do: any_clause_propagates?(keywords, opts)

  defp error_value?({:if, _meta, [_condition, keywords]}, opts) when is_list(keywords),
    do: Enum.any?(keywords, fn {_key, branch} -> propagates_error?(branch, opts) end)

  defp error_value?({:with, _meta, args}, opts) when is_list(args) do
    case List.last(args) do
      keywords when is_list(keywords) -> any_clause_propagates?(keywords, opts)
      _ -> false
    end
  end

  defp error_value?(_expression, _opts), do: false

  defp any_clause_propagates?(keywords, opts) do
    keywords
    |> Enum.flat_map(fn
      {_key, clauses} when is_list(clauses) -> clauses
      {_key, other} -> [other]
    end)
    |> Enum.any?(fn
      {:->, _meta, [_pattern, clause_body]} -> propagates_error?(clause_body, opts)
      other -> propagates_error?(other, opts)
    end)
  end

  defp raises?(body) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {raiser, _meta, _args} = ast, _acc when raiser in [:raise, :reraise] -> {ast, true}
        ast, acc -> {ast, acc}
      end)

    found
  end

  # Accepts both `Module.function` and bare local names, so a project whose
  # reporting goes through a private helper can name that helper instead of
  # being told off on every call site.
  defp calls_any?(body, names) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {{:., _meta, [{:__aliases__, _alias_meta, module_parts}, func]}, _call_meta, _args} = ast,
        acc ->
          full_name = Enum.join(module_parts, ".") <> "." <> to_string(func)
          if full_name in names, do: {ast, true}, else: {ast, acc}

        {func, _meta, args} = ast, acc when is_atom(func) and is_list(args) ->
          if to_string(func) in names, do: {ast, true}, else: {ast, acc}

        ast, acc ->
          {ast, acc}
      end)

    found
  end
end
