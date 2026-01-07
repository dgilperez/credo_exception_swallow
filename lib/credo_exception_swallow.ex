defmodule CredoExceptionSwallow do
  @moduledoc """
  Credo checks to detect silent exception swallowing.

  This library provides custom Credo checks that enforce proper error handling
  in rescue blocks. Silent exception swallowing is a dangerous anti-pattern that
  hides bugs and makes debugging nearly impossible.

  ## Installation

  Add to your `mix.exs`:

      def deps do
        [
          {:credo_exception_swallow, "~> 0.1.0", only: [:dev, :test], runtime: false}
        ]
      end

  ## Configuration

  Add to your `.credo.exs` in the `checks` section:

      {CredoExceptionSwallow.Checks.Warning.SilentRescue, []}

  ## Available Checks

  - `CredoExceptionSwallow.Checks.Warning.SilentRescue` - Detects rescue blocks
    that don't log, report errors, or re-raise exceptions.
  """
end
