defmodule CredoExceptionSwallow.MixProject do
  use Mix.Project

  @version "0.2.1"
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
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      },
      maintainers: ["David Gil"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
