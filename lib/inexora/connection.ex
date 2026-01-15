defmodule Inexora.Connection do
  @moduledoc """
  DBConnection implementation for Oracle database connections.

  This module handles connection lifecycle, transaction management,
  and health checks for Oracle database connections.

  ## Options

  Connection options:

    * `:username` - Database username (required)
    * `:password` - Database password (required)
    * `:database` - Oracle connection string (required), e.g., "localhost:1521/ORCLPDB1"
    * `:hostname` - Database hostname (alternative to connection string)
    * `:port` - Database port (default: 1521)
    * `:service_name` - Oracle service name (alternative to connection string)

  ## Example

      {:ok, conn} = DBConnection.start_link(Inexora.Connection,
        username: "scott",
        password: "tiger",
        database: "localhost:1521/ORCLPDB1"
      )
  """

  use DBConnection

  alias Inexora.Error
  alias Inexora.Nif

  defstruct [
    :context,
    :conn,
    :transaction_status
  ]

  @type t :: %__MODULE__{
          context: reference(),
          conn: reference(),
          transaction_status: :idle | :transaction | :error
        }

  # ============================================================
  # DBConnection Callbacks
  # ============================================================

  @impl DBConnection
  def connect(opts) do
    username = opts |> Keyword.fetch!(:username) |> to_string()
    password = opts |> Keyword.fetch!(:password) |> to_string()
    database = build_connect_string(opts)

    with {:ok, context} <- Nif.context_create(),
         {:ok, conn} <- Nif.conn_create(context, username, password, database) do
      {:ok,
       %__MODULE__{
         context: context,
         conn: conn,
         transaction_status: :idle
       }}
    else
      {:error, reason} -> {:error, Error.from_odpi(reason)}
    end
  end

  @impl DBConnection
  def disconnect(_error, %__MODULE__{conn: conn, context: context} = _state) do
    # Close connection first, then destroy context
    if conn, do: Nif.conn_close(conn)
    if context, do: Nif.context_destroy(context)
    :ok
  end

  @impl DBConnection
  def checkout(%__MODULE__{conn: conn} = state) do
    # Verify connection is healthy before checkout
    case Nif.conn_get_is_healthy(conn) do
      {:ok, true} ->
        {:ok, state}

      {:ok, false} ->
        {:disconnect, Error.from_odpi("connection unhealthy"), state}

      {:error, reason} ->
        {:disconnect, Error.from_odpi(reason), state}
    end
  end

  @impl DBConnection
  def ping(%__MODULE__{conn: conn} = state) do
    case Nif.conn_ping(conn) do
      :ok -> {:ok, state}
      {:error, reason} -> {:disconnect, Error.from_odpi(reason), state}
    end
  end

  @impl DBConnection
  def handle_status(_opts, %__MODULE__{transaction_status: status} = state) do
    {status, state}
  end

  @impl DBConnection
  def handle_begin(_opts, %__MODULE__{transaction_status: :idle} = state) do
    # Oracle uses implicit transactions - no explicit BEGIN needed
    # We just mark that we're in a transaction
    {:ok, :began, %{state | transaction_status: :transaction}}
  end

  def handle_begin(_opts, %__MODULE__{transaction_status: status} = state) do
    {status, state}
  end

  @impl DBConnection
  def handle_commit(_opts, %__MODULE__{transaction_status: :transaction, conn: conn} = state) do
    case Nif.conn_commit(conn) do
      :ok ->
        {:ok, :committed, %{state | transaction_status: :idle}}

      {:error, reason} ->
        {:disconnect, Error.from_odpi(reason), %{state | transaction_status: :error}}
    end
  end

  def handle_commit(_opts, %__MODULE__{transaction_status: status} = state) do
    {status, state}
  end

  @impl DBConnection
  def handle_rollback(_opts, %__MODULE__{transaction_status: :idle} = state) do
    {:idle, state}
  end

  def handle_rollback(_opts, %__MODULE__{conn: conn} = state) do
    case Nif.conn_rollback(conn) do
      :ok ->
        {:ok, :rolledback, %{state | transaction_status: :idle}}

      {:error, reason} ->
        {:disconnect, Error.from_odpi(reason), %{state | transaction_status: :error}}
    end
  end

  # Placeholder implementations for query callbacks (to be implemented later)
  @impl DBConnection
  def handle_prepare(_query, _opts, state) do
    {:error, Error.from_odpi("not implemented"), state}
  end

  @impl DBConnection
  def handle_execute(_query, _params, _opts, state) do
    {:error, Error.from_odpi("not implemented"), state}
  end

  @impl DBConnection
  def handle_close(_query, _opts, state) do
    {:ok, nil, state}
  end

  @impl DBConnection
  def handle_declare(_query, _params, _opts, state) do
    {:error, Error.from_odpi("not implemented"), state}
  end

  @impl DBConnection
  def handle_fetch(_query, _cursor, _opts, state) do
    {:error, Error.from_odpi("not implemented"), state}
  end

  @impl DBConnection
  def handle_deallocate(_query, _cursor, _opts, state) do
    {:ok, nil, state}
  end

  # ============================================================
  # Helper Functions
  # ============================================================

  defp build_connect_string(opts) do
    case Keyword.get(opts, :database) do
      nil ->
        hostname = Keyword.fetch!(opts, :hostname)
        port = Keyword.get(opts, :port, 1521)
        service_name = Keyword.fetch!(opts, :service_name)
        "#{hostname}:#{port}/#{service_name}"

      database ->
        to_string(database)
    end
  end
end
