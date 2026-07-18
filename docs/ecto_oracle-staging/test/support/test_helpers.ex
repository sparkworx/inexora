defmodule EctoOracle.TestHelpers do
  @moduledoc """
  Test helpers for the Ecto Oracle adapter integration suite.

  Compiled only in the `:test` env (see `elixirc_paths/1` in mix.exs).
  """

  @doc """
  Returns the test database connection options, with env-var overrides.

  - `ORACLE_USER`: defaults to `"inexora"` (the schema owner created by
    `docker/init/01_create_user.sql`)
  - `ORACLE_PASSWORD`: defaults to `"Welcome4321"`
  - `ORACLE_DATABASE`: defaults to `"localhost:1521/FREEPDB1"`
  """
  def test_connection_opts do
    [
      username: System.get_env("ORACLE_USER", "inexora"),
      password: System.get_env("ORACLE_PASSWORD", "Welcome4321"),
      database: System.get_env("ORACLE_DATABASE", "localhost:1521/FREEPDB1")
    ]
  end
end
