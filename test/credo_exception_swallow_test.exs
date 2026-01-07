defmodule CredoExceptionSwallowTest do
  use ExUnit.Case

  alias CredoExceptionSwallow.Checks.Warning.SilentRescue

  describe "SilentRescue check" do
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
  end

  defp run_check(code) do
    code
    |> Credo.SourceFile.parse("test.ex")
    |> SilentRescue.run([])
  end
end
