defmodule Ecto.Adapters.Oracle do
  @moduledoc """
  Ecto adapter for Oracle Database using Inexora.

  ## Example

      # In your config/config.exs
      config :my_app, MyApp.Repo,
        adapter: Ecto.Adapters.Oracle,
        username: "scott",
        password: "tiger",
        database: "localhost:1521/ORCLPDB1",
        pool_size: 10

      # In your application
      defmodule MyApp.Repo do
        use Ecto.Repo,
          otp_app: :my_app,
          adapter: Ecto.Adapters.Oracle
      end

  ## Connection options

    * `:username` - Database username (required)
    * `:password` - Database password (required)
    * `:database` - Oracle connection string (required), e.g., "localhost:1521/ORCLPDB1"
    * `:hostname` - Database hostname (alternative to connection string)
    * `:port` - Database port (default: 1521)
    * `:service_name` - Oracle service name (alternative to connection string)
    * `:pool_size` - Number of connections in the pool (default: 10)

  """

  use Ecto.Adapters.SQL,
    driver: :inexora

  @behaviour Ecto.Adapter.Storage

  @impl Ecto.Adapter.Storage
  def storage_up(_opts) do
    # Oracle databases are typically created by DBAs
    {:error, :already_up}
  end

  @impl Ecto.Adapter.Storage
  def storage_down(_opts) do
    # Oracle databases are typically managed by DBAs
    {:error, :already_down}
  end

  @impl Ecto.Adapter.Storage
  def storage_status(_opts) do
    # Would need to check if database exists
    :up
  end

  @doc false
  def supports_ddl_transaction?, do: false

  @doc false
  def lock_for_migrations(_meta, _opts, fun) do
    # Oracle doesn't have advisory locks like PostgreSQL
    # For now, just execute without locking
    {:ok, result, _} = fun.()
    result
  end
end
