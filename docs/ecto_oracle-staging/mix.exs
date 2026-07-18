defmodule EctoOracle.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/sparkworx/ecto_oracle"
  @driver_url "https://github.com/sparkworx/inexora"

  def project do
    [
      app: :ecto_oracle,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),

      # Docs
      name: "Ecto.Adapters.Oracle",
      description: "An Ecto adapter for Oracle Database, built on the inexora driver",
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

  # Compile test/support (TestHelpers) only under the test env.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Tight pre-1.0 lockstep with the driver (ADR-0002 versioning contract):
      # the adapter pins the driver's minor until inexora 1.0, then relaxes to
      # {:inexora, "~> 1.0"}.
      {:inexora, "~> 0.2.0"},
      {:ecto, "~> 3.12"},
      {:ecto_sql, "~> 3.12"},
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
        "Ecto Adapter": [
          Ecto.Adapters.Oracle,
          Ecto.Adapters.Oracle.Connection
        ]
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Ian Woodbury"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "inexora (driver)" => @driver_url
      },
      # No NIF/C sources here — this is a pure-Elixir package; the native driver
      # lives in the `inexora` dependency.
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end
