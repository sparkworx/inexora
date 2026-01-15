defmodule Inexora.MixProject do
  use Mix.Project

  def project do
    [
      app: :inexora,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"]
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
      {:decimal, "~> 2.0"}
    ]
  end
end
