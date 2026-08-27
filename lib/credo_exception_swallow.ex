defmodule CredoExceptionSwallow do
  @moduledoc """
  Credo checks to detect failures that go nowhere.

  This library provides custom Credo checks that enforce proper error handling:
  in `rescue` blocks, and in the error branches that never raise anything at all.
  Both hide bugs and make debugging nearly impossible.

  ## Installation

  Add to your `mix.exs`:

      def deps do
        [
          {:credo_exception_swallow, "~> 0.3.0", only: [:dev, :test], runtime: false}
        ]
      end

  ## Configuration

  Add to your `.credo.exs` in the `checks` section:

      {CredoExceptionSwallow.Checks.Warning.SilentRescue, []},
      {CredoExceptionSwallow.Checks.Warning.LoggedAndDroppedError, []}

  ## Available Checks

  - `CredoExceptionSwallow.Checks.Warning.SilentRescue` - Detects rescue blocks
    that don't log, report errors, or re-raise exceptions.
  - `CredoExceptionSwallow.Checks.Warning.LoggedAndDroppedError` - Detects
    `{:error, _}` branches that log a warning and then return a success-shaped
    value, so the batch reports `{:ok, ...}` while the row is gone.
  """
end
