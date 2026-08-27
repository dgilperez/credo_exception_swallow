defmodule CredoExceptionSwallow.LoggedAndDroppedErrorTest do
  use ExUnit.Case, async: true

  alias CredoExceptionSwallow.Checks.Warning.LoggedAndDroppedError

  describe "case clauses" do
    test "flags an error branch that logs and returns a success-shaped value" do
      code = """
      defmodule Sync do
        def reduce(row, acc) do
          case upsert(row) do
            {:ok, _} -> bump(acc, :rows_created)
            {:error, reason} ->
              Logger.warning("upsert failed: \#{inspect(reason)}")
              bump(acc, nil)
          end
        end
      end
      """

      assert [issue] = run_check(code)
      assert issue.message =~ "logged and then dropped"
    end

    test "accepts a branch that propagates the error" do
      code = """
      defmodule Sync do
        def reduce(row) do
          case upsert(row) do
            {:ok, value} -> {:ok, value}
            {:error, reason} ->
              Logger.warning("upsert failed")
              {:error, reason}
          end
        end
      end
      """

      assert run_check(code) == []
    end

    test "accepts a branch that reports the failure" do
      code = """
      defmodule Sync do
        def reduce(row, acc) do
          case upsert(row) do
            {:ok, _} -> bump(acc, :rows_created)
            {:error, reason} ->
              Logger.warning("upsert failed")
              ErrorReporter.report_message("upsert failed", %{reason: inspect(reason)})
              bump(acc, nil)
          end
        end
      end
      """

      assert run_check(code) == []
    end

    test "accepts a branch that raises" do
      code = """
      defmodule Sync do
        def reduce(row, acc) do
          case upsert(row) do
            {:ok, _} -> acc
            {:error, reason} ->
              Logger.error("upsert failed")
              raise "upsert failed: \#{inspect(reason)}"
          end
        end
      end
      """

      assert run_check(code) == []
    end

    test "ignores a branch that never claimed the failure mattered" do
      code = """
      defmodule Web do
        def save(socket, attrs) do
          case Context.create(attrs) do
            {:ok, record} -> {:noreply, assign(socket, :record, record)}
            {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
          end
        end
      end
      """

      assert run_check(code) == [],
             "a handled error with no warning is not a swallowed one"
    end

    test "ignores Logger.info and Logger.debug" do
      code = """
      defmodule Sync do
        def reduce(row, acc) do
          case upsert(row) do
            {:ok, _} -> acc
            {:error, _reason} ->
              Logger.info("nothing to do")
              acc
          end
        end
      end
      """

      assert run_check(code) == []
    end

    test "flags a three-element error tuple" do
      code = """
      defmodule Sync do
        def reduce(row, acc) do
          case map(row) do
            {:ok, mapped} -> persist(mapped, acc)
            {:error, reason, _meta} ->
              Logger.warning("mapping failed: \#{inspect(reason)}")
              acc
          end
        end
      end
      """

      assert [_issue] = run_check(code)
    end

    test "flags a bare :error clause" do
      code = """
      defmodule Sync do
        def reduce(row, acc) do
          case fetch(row) do
            {:ok, value} -> value
            :error ->
              Logger.warning("nothing came back")
              acc
          end
        end
      end
      """

      assert [_issue] = run_check(code)
    end
  end

  describe "with/else clauses" do
    test "flags an else branch that logs and swallows" do
      code = """
      defmodule Sync do
        def run(id, acc) do
          with {:ok, row} <- fetch(id),
               {:ok, saved} <- persist(row) do
            bump(acc, saved)
          else
            {:error, reason} ->
              Logger.warning("sync failed: \#{inspect(reason)}")
              bump(acc, nil)
          end
        end
      end
      """

      assert [_issue] = run_check(code)
    end
  end

  describe "function heads" do
    test "flags a head that matches the failure and drops it" do
      code = """
      defmodule Sync do
        defp reduce({:error, reason, _meta}, acc) do
          Logger.warning("mapping failed: \#{inspect(reason)}")
          acc
        end
      end
      """

      assert [_issue] = run_check(code)
    end

    test "accepts a head that reports before dropping" do
      code = """
      defmodule Sync do
        defp reduce({:error, reason}, acc) do
          Logger.warning("mapping failed")
          Sentry.capture_message("mapping failed", extra: %{reason: inspect(reason)})
          acc
        end
      end
      """

      assert run_check(code) == []
    end
  end

  describe "configuration" do
    test "skips test files by default" do
      code = """
      defmodule SyncTest do
        def reduce(row, acc) do
          case upsert(row) do
            {:ok, _} -> acc
            {:error, _reason} ->
              Logger.warning("boom")
              acc
          end
        end
      end
      """

      assert run_check(code, "sync_test.exs") == []
      assert [_issue] = run_check(code, "sync_test.exs", skip_test_files: false)
    end

    test "honours a custom reporting_calls list" do
      code = """
      defmodule Sync do
        def reduce(row, acc) do
          case upsert(row) do
            {:ok, _} -> acc
            {:error, reason} ->
              Logger.warning("boom")
              Telemetry.failure(reason)
              acc
          end
        end
      end
      """

      assert [_issue] = run_check(code)
      assert run_check(code, "sync.ex", reporting_calls: ["Telemetry.failure"]) == []
    end
  end

  describe "propagation the check must not miss" do
    test "accepts a branch that hands back the bound error variable" do
      code = """
      defmodule Worker do
        def rehost(activity) do
          case fetch(activity) do
            {:ok, body} -> store(body)
            {:error, reason} = err ->
              Logger.warning("rehost failed: \#{inspect(reason)}")
              err
          end
        end
      end
      """

      assert run_check(code) == [],
             "returning the error under another name is still propagating it"
    end

    test "accepts reporting through a project-local helper when configured" do
      code = """
      defmodule Sync do
        defp reduce({:error, reason, meta}, acc) do
          report_degraded(meta, reason)
          Logger.warning("mapping failed")
          acc
        end
      end
      """

      assert [_issue] = run_check(code)
      assert run_check(code, "sync.ex", reporting_calls: ["report_degraded"]) == []
    end

    test "accepts a trailing case whose branches propagate" do
      code = """
      defmodule Sync do
        def run(row) do
          case upsert(row) do
            {:ok, value} -> {:ok, value}
            {:error, reason} ->
              Logger.warning("upsert failed")

              case retry(row) do
                {:ok, value} -> {:ok, value}
                _ -> {:error, reason}
              end
          end
        end
      end
      """

      assert run_check(code) == []
    end
  end

  describe "clause shapes the first cut missed" do
    test "flags a reduce callback, where the error is one pattern among several" do
      code = """
      defmodule Sync do
        def run(rows, acc) do
          Enum.reduce(rows, acc, fn
            {:ok, row}, acc -> bump(acc, row)
            {:error, reason}, acc ->
              Logger.warning("row failed: \#{inspect(reason)}")
              acc
          end)
        end
      end
      """

      assert [_issue] = run_check(code),
             "every Enum.reduce callback has more than one pattern"
    end

    test "flags a guarded clause" do
      code = """
      defmodule Sync do
        def run(row, acc) do
          case upsert(row) do
            {:ok, _} -> acc
            {:error, reason} when is_atom(reason) ->
              Logger.warning("row failed")
              acc
          end
        end
      end
      """

      assert [_issue] = run_check(code)
    end

    test "flags a guarded function head" do
      code = """
      defmodule Sync do
        defp reduce({:error, reason}, acc) when is_map(acc) do
          Logger.warning("row failed: \#{inspect(reason)}")
          acc
        end
      end
      """

      assert [_issue] = run_check(code)
    end

    test "accepts a branch that carries the failure into the value it returns" do
      code = """
      defmodule Sync do
        def run(rows) do
          Enum.reduce(rows, {0, []}, fn
            {:ok, _row}, {count, errs} -> {count + 1, errs}
            {:error, reason}, {count, errs} ->
              Logger.warning("row failed")
              {count, [reason | errs]}
          end)
        end
      end
      """

      assert run_check(code) == [],
             "the failure survives in the returned value; the caller can still report it"
    end

    test "an accumulator next to the error is not the error travelling onwards" do
      code = """
      defmodule Sync do
        def run(rows, acc) do
          Enum.reduce(rows, acc, fn
            {:ok, row}, acc -> bump(acc, row)
            {:error, _reason}, acc ->
              Logger.warning("row failed")
              acc
          end)
        end
      end
      """

      assert [_issue] = run_check(code)
    end
  end

  describe "retry loops" do
    test "accepts a branch that retries by calling its own function" do
      code = """
      defmodule Client do
        defp query(url, retries_left) do
          case request(url) do
            {:ok, body} -> {:ok, body}
            {:error, reason} when retries_left > 0 ->
              Logger.warning("retrying after \#{inspect(reason)}")
              query(url, retries_left - 1)
          end
        end
      end
      """

      assert run_check(code) == [],
             "the operation carries on; nothing has been dropped yet"
    end

    test "still flags a branch that calls a different function and drops the failure" do
      code = """
      defmodule Client do
        defp query(url, acc) do
          case request(url) do
            {:ok, body} -> {:ok, body}
            {:error, _reason} ->
              Logger.warning("gave up")
              give_up(acc)
          end
        end
      end
      """

      assert [_issue] = run_check(code)
    end
  end

  describe "handing the failure on" do
    test "accepts a GenServer that reschedules itself" do
      code = """
      defmodule Publisher do
        def handle_info(:connect, state) do
          case connect() do
            {:ok, conn} -> {:noreply, %{state | conn: conn}}
            {:error, reason} ->
              Logger.warning("connection failed: \#{inspect(reason)}; retrying")
              Process.send_after(self(), :connect, 5_000)
              {:noreply, state}
          end
        end
      end
      """

      assert run_check(code) == []
    end

    test "accepts a configured propagating call, and flags it without the config" do
      code = """
      defmodule Controller do
        def cancel(conn, params) do
          case Sessions.cancel(params) do
            {:ok, count} -> json(conn, %{cancelled: count})
            {:error, reason} ->
              Logger.warning("cancellation failed: \#{inspect(reason)}")
              send_error(conn, :unprocessable_entity, "Could not cancel")
          end
        end
      end
      """

      assert [_issue] = run_check(code)
      assert run_check(code, "controller.ex", propagating_calls: ["send_error"]) == []
    end
  end

  defp run_check(code, filename \\ "sync.ex", params \\ []) do
    code
    |> Credo.SourceFile.parse(filename)
    |> LoggedAndDroppedError.run(params)
  end
end
