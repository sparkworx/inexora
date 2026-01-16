defmodule Inexora.TestHelpers do
  @moduledoc """
  Centralized test helpers for Inexora tests.

  Provides common database connection functions with correct default credentials.
  """

  alias Inexora.Connection
  alias Inexora.Nif

  @doc """
  Returns the test database connection options with correct defaults.

  Credentials are loaded from environment variables with fallbacks:
  - ORACLE_USER: defaults to "inexora"
  - ORACLE_PASSWORD: defaults to "Welcome4321"
  - ORACLE_DATABASE: defaults to "localhost:1521/FREEPDB1"
  """
  def test_connection_opts do
    [
      username: System.get_env("ORACLE_USER", "inexora"),
      password: System.get_env("ORACLE_PASSWORD", "Welcome4321"),
      database: System.get_env("ORACLE_DATABASE", "localhost:1521/FREEPDB1")
    ]
  end

  @doc """
  Connects to the test database using the Connection module.

  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  def connect_test_db do
    Connection.connect(test_connection_opts())
  end

  @doc """
  Connects to the test database using low-level NIF functions.

  Returns `{:ok, ctx, conn}` on success or `{:error, reason}` on failure.
  This is useful for tests that need direct access to the context and connection
  references without the Connection module abstraction.
  """
  def connect_test_db_nif do
    {:ok, ctx} = Nif.context_create()

    opts = test_connection_opts()
    username = Keyword.fetch!(opts, :username)
    password = Keyword.fetch!(opts, :password)
    database = Keyword.fetch!(opts, :database)

    case Nif.conn_create(ctx, username, password, database) do
      {:ok, conn} -> {:ok, ctx, conn}
      {:error, _} = error -> error
    end
  end

  @doc """
  Cleans up NIF-level connection resources.

  Should be called in an `after` block when using `connect_test_db_nif/0`.
  """
  def cleanup_nif(ctx, conn) do
    Nif.conn_close(conn)
    Nif.context_destroy(ctx)
  end
end
