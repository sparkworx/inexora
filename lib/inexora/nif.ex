defmodule Inexora.Nif do
  @moduledoc """
  Low-level NIF bindings to ODPI-C.

  This module provides the raw NIF function stubs that interface
  with the ODPI-C library. Higher-level APIs should be built on top.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    path = :filename.join(:code.priv_dir(:inexora), ~c"inexora_nif")
    :erlang.load_nif(path, 0)
  end

  @type context :: reference()
  @type conn :: reference()
  @type stmt :: reference()
  @type reason :: atom() | String.t() | {integer(), String.t(), String.t()}
  @type column_info :: %{
          name: String.t(),
          oracle_type: non_neg_integer(),
          native_type: non_neg_integer(),
          db_size: non_neg_integer(),
          client_size: non_neg_integer(),
          precision: integer(),
          scale: integer(),
          null_ok: boolean()
        }

  @doc """
  Returns the ODPI-C library version as a tuple.

  This function does NOT require Oracle Instant Client to be installed.

  ## Examples

      iex> Inexora.Nif.odpi_version()
      {:ok, {5, 6, 4}}
  """
  @spec odpi_version() :: {:ok, {integer(), integer(), integer()}} | {:error, reason()}
  def odpi_version, do: :erlang.nif_error(:not_loaded)

  @doc """
  Creates a new ODPI-C context.

  Note: This will fail if Oracle Instant Client is not installed and
  accessible in the library path.

  ## Examples

      iex> {:ok, ctx} = Inexora.Nif.context_create()
      iex> is_reference(ctx)
      true
  """
  @spec context_create() :: {:ok, context()} | {:error, reason()}
  def context_create, do: :erlang.nif_error(:not_loaded)

  @doc """
  Destroys a ODPI-C context.

  ## Examples

      iex> {:ok, ctx} = Inexora.Nif.context_create()
      iex> Inexora.Nif.context_destroy(ctx)
      :ok
  """
  @spec context_destroy(context()) :: :ok | {:error, reason()}
  def context_destroy(_context), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the Oracle client version.

  Requires a valid context and Oracle Instant Client installed.
  Returns `{version, release, update, port_release, port_update}`.

  ## Examples

      iex> {:ok, ctx} = Inexora.Nif.context_create()
      iex> {:ok, {major, _, _, _, _}} = Inexora.Nif.get_client_version(ctx)
      iex> major >= 11
      true
  """
  @spec get_client_version(context()) ::
          {:ok, {integer(), integer(), integer(), integer(), integer()}} | {:error, reason()}
  def get_client_version(_context), do: :erlang.nif_error(:not_loaded)

  # ============================================================
  # Connection Functions
  # ============================================================

  @doc """
  Creates a new database connection.

  ## Parameters

    * `context` - ODPI-C context reference
    * `username` - Database username (binary)
    * `password` - Database password (binary)
    * `connect_string` - Oracle connection string (binary), e.g., "localhost:1521/ORCLPDB1"

  ## Examples

      iex> {:ok, ctx} = Inexora.Nif.context_create()
      iex> {:ok, conn} = Inexora.Nif.conn_create(ctx, "user", "password", "localhost:1521/ORCLPDB1")
  """
  @spec conn_create(context(), binary(), binary(), binary()) :: {:ok, conn()} | {:error, reason()}
  def conn_create(_context, _username, _password, _connect_string),
    do: :erlang.nif_error(:not_loaded)

  @doc """
  Closes a database connection.

  The connection is closed and released. After calling this function,
  the connection reference should not be used.
  """
  @spec conn_close(conn()) :: :ok | {:error, reason()}
  def conn_close(_conn), do: :erlang.nif_error(:not_loaded)

  @doc """
  Pings the database to verify the connection is alive.

  This performs a round-trip to the database server.
  """
  @spec conn_ping(conn()) :: :ok | {:error, reason()}
  def conn_ping(_conn), do: :erlang.nif_error(:not_loaded)

  @doc """
  Commits the current transaction.
  """
  @spec conn_commit(conn()) :: :ok | {:error, reason()}
  def conn_commit(_conn), do: :erlang.nif_error(:not_loaded)

  @doc """
  Rolls back the current transaction.
  """
  @spec conn_rollback(conn()) :: :ok | {:error, reason()}
  def conn_rollback(_conn), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the Oracle server version.

  Returns a tuple of `{release_string, version_info}` where `version_info`
  is `{version, release, update, port_release, port_update}`.
  """
  @spec conn_get_server_version(conn()) ::
          {:ok, {String.t(), {integer(), integer(), integer(), integer(), integer()}}}
          | {:error, reason()}
  def conn_get_server_version(_conn), do: :erlang.nif_error(:not_loaded)

  @doc """
  Checks if the connection is healthy without a round-trip to the server.

  This is a quick local check based on the connection state.
  """
  @spec conn_get_is_healthy(conn()) :: {:ok, boolean()} | {:error, reason()}
  def conn_get_is_healthy(_conn), do: :erlang.nif_error(:not_loaded)

  @doc """
  Checks if a transaction is currently in progress on the connection.
  """
  @spec conn_get_transaction_in_progress(conn()) :: {:ok, boolean()} | {:error, reason()}
  def conn_get_transaction_in_progress(_conn), do: :erlang.nif_error(:not_loaded)

  # ============================================================
  # Statement Functions
  # ============================================================

  @doc """
  Prepares a SQL statement for execution.

  ## Parameters

    * `conn` - Database connection reference
    * `sql` - SQL statement string (binary)

  ## Examples

      iex> {:ok, stmt} = Inexora.Nif.stmt_prepare(conn, "SELECT 1 FROM dual")
  """
  @spec stmt_prepare(conn(), binary()) :: {:ok, stmt()} | {:error, reason()}
  def stmt_prepare(_conn, _sql), do: :erlang.nif_error(:not_loaded)

  @doc """
  Executes a prepared statement.

  Returns the number of columns for SELECT statements, or 0 for DML.
  """
  @spec stmt_execute(stmt()) :: {:ok, non_neg_integer()} | {:error, reason()}
  def stmt_execute(_stmt), do: :erlang.nif_error(:not_loaded)

  @doc """
  Fetches the next row from a SELECT statement.

  Returns `{:ok, true}` if a row was fetched, `{:ok, :done}` if no more rows.
  """
  @spec stmt_fetch(stmt()) :: {:ok, true | :done} | {:error, reason()}
  def stmt_fetch(_stmt), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets column metadata for a query at the given position (1-based).

  Returns a map with column information including name, type, size, etc.
  """
  @spec stmt_get_query_info(stmt(), pos_integer()) :: {:ok, column_info()} | {:error, reason()}
  def stmt_get_query_info(_stmt, _pos), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the value at the given column position (1-based) for the current row.

  The value is converted to an appropriate Elixir type based on the Oracle data type.
  """
  @spec stmt_get_query_value(stmt(), pos_integer()) :: {:ok, term()} | {:error, reason()}
  def stmt_get_query_value(_stmt, _pos), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the number of rows affected by a DML statement.
  """
  @spec stmt_get_row_count(stmt()) :: {:ok, non_neg_integer()} | {:error, reason()}
  def stmt_get_row_count(_stmt), do: :erlang.nif_error(:not_loaded)

  @doc """
  Binds a value to a parameter at the given position (1-based).

  ## Parameters

    * `stmt` - Statement reference
    * `pos` - Parameter position (1-based)
    * `type` - Type hint atom: `:integer`, `:float`, `:string`, `:binary`
    * `value` - The value to bind (or `nil` for NULL)
  """
  @spec stmt_bind_value_by_pos(stmt(), pos_integer(), atom(), term()) :: :ok | {:error, reason()}
  def stmt_bind_value_by_pos(_stmt, _pos, _type, _value), do: :erlang.nif_error(:not_loaded)

  @doc """
  Closes and releases a prepared statement.
  """
  @spec stmt_close(stmt()) :: :ok | {:error, reason()}
  def stmt_close(_stmt), do: :erlang.nif_error(:not_loaded)
end
