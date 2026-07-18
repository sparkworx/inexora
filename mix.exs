defmodule Inexora.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/sparkworx/inexora"

  def project do
    [
      app: :inexora,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],

      # Docs
      name: "Inexora",
      description: "An Oracle Database driver for Elixir, built on ODPI-C",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false},
      {:db_connection, "~> 2.6"},
      {:decimal, "~> 2.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        Driver: [
          Inexora,
          Inexora.Connection,
          Inexora.Query,
          Inexora.Result,
          Inexora.Error
        ],
        "Low-Level": [
          Inexora.Nif,
          Inexora.Type,
          Inexora.Cursor,
          Inexora.Batch
        ]
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Ian Woodbury"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url
      },
      # `priv` is intentionally omitted: the NIF is built from source on the
      # installer's machine via elixir_make (the Makefile's `all` target creates
      # priv/), so shipping a locally-compiled, platform-specific .so is both
      # unnecessary and wrong for other platforms.
      files: ~w(lib c_src .formatter.exs mix.exs README.md CHANGELOG.md LICENSE Makefile)
    ]
  end
end
