defmodule CredoExceptionSwallowTest do
  use ExUnit.Case

  alias CredoExceptionSwallow.Checks.Warning.SilentRescue

  describe "try/rescue blocks" do
    test "detects silent rescue block" do
      code = """
      defmodule BadExample do
        def risky do
          try do
            something()
          rescue
            _ -> :ok
          end
        end
      end
      """

      issues = run_check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "silently swallows exception"
    end

    test "detects multiple silent rescue clauses" do
      code = """
      defmodule BadExample do
        def risky do
          try do
            something()
          rescue
            ArgumentError -> :arg_error
            RuntimeError -> :runtime_error
          end
        end
      end
      """

      issues = run_check(code)
      assert length(issues) == 2
    end

    test "allows rescue with Logger.error" do
      code = """
      defmodule GoodExample do
        require Logger
        def risky do
          try do
            something()
          rescue
            e ->
              Logger.error("Failed: \#{inspect(e)}")
              :error
          end
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end

    test "allows rescue with Logger.warning" do
      code = """
      defmodule GoodExample do
        require Logger
        def risky do
          try do
            something()
          rescue
            e ->
              Logger.warning("Failed: \#{inspect(e)}")
              :error
          end
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end

    test "allows rescue with reraise" do
      code = """
      defmodule GoodExample do
        def risky do
          try do
            something()
          rescue
            e -> reraise e, __STACKTRACE__
          end
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end

    test "allows rescue with Sentry.capture_exception" do
      code = """
      defmodule GoodExample do
        def risky do
          try do
            something()
          rescue
            e ->
              Sentry.capture_exception(e)
              :error
          end
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end

    test "allows rescue with ErrorReporter.report_exception" do
      code = """
      defmodule GoodExample do
        def risky do
          try do
            something()
          rescue
            e ->
              ErrorReporter.report_exception(e, %{})
              :error
          end
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end

    test "allows rescue with ErrorReporter.report_message" do
      code = """
      defmodule GoodExample do
        def risky do
          try do
            something()
          rescue
            e ->
              ErrorReporter.report_message("failed", %{error: e})
              :error
          end
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end

    test "allows rescue with custom acceptable call configuration" do
      code = """
      defmodule GoodExample do
        def risky do
          try do
            something()
          rescue
            e ->
              MyApp.ErrorReporter.capture_exception(e, stacktrace: __STACKTRACE__)
              :error
          end
        end
      end
      """

      issues =
        run_check(code, "test.ex", acceptable_calls: ["MyApp.ErrorReporter.capture_exception"])

      assert issues == []
    end
  end

  describe "function-level rescue blocks" do
    test "detects silent function-level rescue with bare underscore" do
      code = """
      defmodule BadExample do
        defp load_data(id) do
          Repo.all(from(d in Data, where: d.id == ^id))
        rescue
          _ -> []
        end
      end
      """

      issues = run_check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "silently swallows exception"
    end

    test "detects silent function-level rescue with named variable" do
      code = """
      defmodule BadExample do
        def fetch(id) do
          do_fetch(id)
        rescue
          _error -> {:error, :failed}
        end
      end
      """

      issues = run_check(code)
      assert length(issues) == 1
    end

    test "detects silent rescue in public def" do
      code = """
      defmodule BadExample do
        def public_method do
          risky()
        rescue
          ArgumentError -> nil
        end
      end
      """

      issues = run_check(code)
      assert length(issues) == 1
    end

    test "detects multiple function-level rescue clauses" do
      code = """
      defmodule BadExample do
        defp load(id) do
          query(id)
        rescue
          Ecto.QueryError -> 0
          MyXQL.Error -> 0
        end
      end
      """

      issues = run_check(code)
      assert length(issues) == 2
    end

    test "allows function-level rescue with Logger" do
      code = """
      defmodule GoodExample do
        require Logger
        defp load_data(id) do
          Repo.all(from(d in Data, where: d.id == ^id))
        rescue
          error ->
            Logger.error("Failed to load: \#{inspect(error)}")
            []
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end

    test "allows function-level rescue with ErrorReporter" do
      code = """
      defmodule GoodExample do
        defp load_data(id) do
          Repo.all(from(d in Data, where: d.id == ^id))
        rescue
          error ->
            ErrorReporter.report_exception(error, %{context: "load_data"})
            []
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end

    test "allows function-level rescue with reraise" do
      code = """
      defmodule GoodExample do
        defp load_data(id) do
          Repo.all(from(d in Data, where: d.id == ^id))
        rescue
          error ->
            reraise error, __STACKTRACE__
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end
  end

  describe "accumulator correctness" do
    test "Logger call followed by other code still passes" do
      code = """
      defmodule GoodExample do
        require Logger
        def risky do
          try do
            something()
          rescue
            e ->
              Logger.error("Failed: \#{inspect(e)}")
              some_other_function()
              :error
          end
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end

    test "Logger and ErrorReporter together passes" do
      code = """
      defmodule GoodExample do
        require Logger
        def risky do
          try do
            something()
          rescue
            e ->
              Logger.error("Failed: \#{inspect(e)}")
              ErrorReporter.report_exception(e, %{})
              :error
          end
        end
      end
      """

      issues = run_check(code)
      assert issues == []
    end
  end

  describe "mixed scenarios" do
    test "detects issues in both try/rescue and function-level rescue" do
      code = """
      defmodule MixedExample do
        defp silent_function do
          query()
        rescue
          _ -> nil
        end

        def also_silent do
          try do
            something()
          rescue
            _ -> :ok
          end
        end
      end
      """

      issues = run_check(code)
      assert length(issues) == 2
    end

    test "one good and one bad rescue" do
      code = """
      defmodule MixedExample do
        require Logger

        defp good_function do
          query()
        rescue
          error ->
            Logger.error("boom: \#{inspect(error)}")
            nil
        end

        defp bad_function do
          query()
        rescue
          _ -> nil
        end
      end
      """

      issues = run_check(code)
      assert length(issues) == 1
    end
  end

  describe "test file skipping" do
    test "skips test files by default" do
      code = """
      defmodule BadExampleTest do
        def risky do
          try do
            something()
          rescue
            _ -> :ok
          end
        end
      end
      """

      issues = run_check(code, "some_test.exs")
      assert issues == []
    end

    test "checks test files when configured" do
      code = """
      defmodule BadExampleTest do
        def risky do
          try do
            something()
          rescue
            _ -> :ok
          end
        end
      end
      """

      issues = run_check(code, "some_test.exs", skip_test_files: false)
      assert length(issues) == 1
    end
  end

  defp run_check(code, filename \\ "test.ex", params \\ []) do
    code
    |> Credo.SourceFile.parse(filename)
    |> SilentRescue.run(params)
  end
end
