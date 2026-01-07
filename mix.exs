defmodule CredoExceptionSwallow.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dgilperez/credo_exception_swallow"

  def project do
    [
      app: :credo_exception_swallow,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "CredoExceptionSwallow",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Credo check to detect silent exception swallowing in rescue blocks.
    Enforces proper error handling by requiring logging, error reporting, or re-raising.
    """
  end

  defp package do
    [
      name: "credo_exception_swallow",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["David Gil"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
