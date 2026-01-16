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
  alias Inexora.Query
  alias Inexora.Result
  alias Inexora.Type

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

  # ============================================================
  # Query Callbacks
  # ============================================================

  @impl DBConnection
  def handle_prepare(%Query{sql: sql} = query, _opts, %__MODULE__{conn: conn} = state) do
    case Nif.stmt_prepare(conn, sql) do
      {:ok, stmt} ->
        {:ok, %{query | statement: stmt}, state}

      {:error, reason} ->
        {:error, Error.from_odpi(reason), state}
    end
  end

  def handle_prepare(sql, opts, state) when is_binary(sql) do
    handle_prepare(Query.new(sql), opts, state)
  end

  @impl DBConnection
  def handle_execute(%Query{statement: stmt} = query, params, _opts, state) when is_reference(stmt) do
    with :ok <- bind_params(stmt, params),
         {:ok, num_columns} <- Nif.stmt_execute(stmt) do
      if num_columns > 0 do
        # SELECT query - fetch results
        execute_select(query, num_columns, state)
      else
        # DML statement - get row count
        execute_dml(stmt, state)
      end
    else
      {:error, reason} ->
        {:error, Error.from_odpi(reason), state}
    end
  end

  def handle_execute(%Query{} = query, params, opts, state) do
    # Query not prepared yet - prepare and execute
    case handle_prepare(query, opts, state) do
      {:ok, prepared_query, state} ->
        handle_execute(prepared_query, params, opts, state)

      {:error, _reason, _state} = error ->
        error
    end
  end

  @impl DBConnection
  def handle_close(%Query{statement: stmt}, _opts, state) when is_reference(stmt) do
    Nif.stmt_close(stmt)
    {:ok, nil, state}
  end

  def handle_close(_query, _opts, state) do
    {:ok, nil, state}
  end

  @impl DBConnection
  def handle_declare(_query, _params, _opts, state) do
    # Cursors not yet supported
    {:error, Error.from_odpi("cursors not implemented"), state}
  end

  @impl DBConnection
  def handle_fetch(_query, _cursor, _opts, state) do
    {:error, Error.from_odpi("cursors not implemented"), state}
  end

  @impl DBConnection
  def handle_deallocate(_query, _cursor, _opts, state) do
    {:ok, nil, state}
  end

  # ============================================================
  # Query Execution Helpers
  # ============================================================

  defp bind_params(_stmt, []), do: :ok

  defp bind_params(stmt, params) do
    params
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {value, pos}, :ok ->
      type_hint = Type.type_hint(value)
      encoded_value = Type.encode(value)

      case Nif.stmt_bind_value_by_pos(stmt, pos, type_hint, encoded_value) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp execute_select(%Query{statement: stmt}, num_columns, state) do
    # Get column metadata
    columns =
      for pos <- 1..num_columns do
        case Nif.stmt_get_query_info(stmt, pos) do
          {:ok, info} -> info
          {:error, _} -> %{name: "col_#{pos}"}
        end
      end

    column_names = Enum.map(columns, & &1[:name])

    # Fetch all rows
    rows = fetch_all_rows(stmt, num_columns, columns)

    result = Result.new_select(column_names, rows)
    {:ok, %Query{statement: stmt}, result, state}
  end

  defp execute_dml(stmt, state) do
    case Nif.stmt_get_row_count(stmt) do
      {:ok, count} ->
        result = Result.new_dml(count)
        {:ok, %Query{statement: stmt}, result, state}

      {:error, reason} ->
        {:error, Error.from_odpi(reason), state}
    end
  end

  defp fetch_all_rows(stmt, num_columns, columns) do
    fetch_rows_loop(stmt, num_columns, columns, [])
  end

  defp fetch_rows_loop(stmt, num_columns, columns, acc) do
    case Nif.stmt_fetch(stmt) do
      {:ok, true} ->
        row = fetch_row_values(stmt, num_columns, columns)
        fetch_rows_loop(stmt, num_columns, columns, [row | acc])

      {:ok, :done} ->
        Enum.reverse(acc)

      {:error, _reason} ->
        Enum.reverse(acc)
    end
  end

  defp fetch_row_values(stmt, num_columns, columns) do
    for pos <- 1..num_columns do
      column_info = Enum.at(columns, pos - 1)

      case Nif.stmt_get_query_value(stmt, pos) do
        {:ok, value} -> Type.to_elixir(value, column_info)
        {:error, _} -> nil
      end
    end
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
