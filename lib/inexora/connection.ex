defmodule Inexora.Connection do
  @moduledoc """
  DBConnection implementation for Oracle database connections.

  This module handles connection lifecycle, transaction management,
  and health checks for Oracle database connections.

  ## Options

  Connection options:

    * `:username` - Database username (optional, omit for Oracle Wallet authentication)
    * `:password` - Database password (optional, omit for Oracle Wallet authentication)
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
    username = opts |> Keyword.get(:username, "") |> to_string()
    password = opts |> Keyword.get(:password, "") |> to_string()
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
    # Ensure SQL is a binary (Ecto adapters often return iodata)
    sql_binary = IO.iodata_to_binary(sql)

    case Nif.stmt_prepare(conn, sql_binary) do
      {:ok, stmt} ->
        {:ok, %{query | statement: stmt, sql: sql_binary}, state}

      {:error, reason} ->
        execute_disposition(reason, state)
    end
  end

  def handle_prepare(sql, opts, state) when is_binary(sql) do
    handle_prepare(Query.new(sql), opts, state)
  end

  def handle_prepare(sql, opts, state) when is_list(sql) do
    # Handle iodata (list) SQL
    handle_prepare(Query.new(IO.iodata_to_binary(sql)), opts, state)
  end

  @impl DBConnection
  def handle_execute(%Query{statement: stmt, returning: returning} = query, params, _opts, state)
      when is_reference(stmt) and returning != nil do
    # DML with RETURNING INTO - use Variable API for output binds
    execute_with_returning(query, params, state)
  end

  def handle_execute(%Query{statement: stmt, sql: sql} = query, params, _opts, state)
      when is_reference(stmt) do
    with :ok <- bind_params(stmt, params),
         {:ok, num_columns} <- Nif.stmt_execute(stmt) do
      if num_columns > 0 do
        # SELECT query - fetch results
        execute_select(query, num_columns, state)
      else
        # DML statement - get row count
        execute_dml(stmt, sql, state)
      end
    else
      {:error, reason} ->
        execute_disposition(reason, state)
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
  def handle_declare(%Query{sql: sql} = query, params, opts, %__MODULE__{conn: conn} = state) do
    # Ensure SQL is a binary
    sql_binary = IO.iodata_to_binary(sql)
    max_rows = Keyword.get(opts, :max_rows, 100)

    with {:ok, stmt} <- Nif.stmt_prepare(conn, sql_binary),
         :ok <- bind_params(stmt, params),
         :ok <- configure_cursor(stmt, opts),
         {:ok, num_columns} <- Nif.stmt_execute(stmt) do
      if num_columns > 0 do
        # Get column metadata
        columns =
          for pos <- 1..num_columns do
            case Nif.stmt_get_query_info(stmt, pos) do
              {:ok, info} -> info
              {:error, _} -> %{name: "col_#{pos}"}
            end
          end

        # Define NUMBER columns to be fetched as bytes for precision
        define_number_columns_as_bytes(stmt, columns)

        cursor = %{
          stmt: stmt,
          columns: columns,
          num_columns: num_columns,
          max_rows: max_rows,
          done: false
        }

        {:ok, %{query | statement: stmt, num_columns: num_columns, columns: columns}, cursor,
         state}
      else
        Nif.stmt_close(stmt)
        {:error, Error.from_odpi("not a query - no columns returned"), state}
      end
    else
      {:error, reason} ->
        execute_disposition(reason, state)
    end
  end

  @impl DBConnection
  def handle_fetch(_query, %{done: true} = cursor, _opts, state) do
    {:halt, [], cursor, state}
  end

  def handle_fetch(
        _query,
        %{stmt: stmt, num_columns: num_columns, columns: columns, max_rows: max_rows} = cursor,
        _opts,
        state
      ) do
    case Nif.stmt_fetch_rows(stmt, max_rows) do
      {:ok, {0, _buffer_idx, _more}} ->
        {:halt, [], %{cursor | done: true}, state}

      {:ok, {rows_fetched, _buffer_idx, more}} ->
        rows = fetch_cursor_rows(stmt, num_columns, columns, rows_fetched)
        done = not more or rows_fetched == 0

        if done do
          {:halt, rows, %{cursor | done: true}, state}
        else
          {:cont, rows, cursor, state}
        end

      {:error, reason} ->
        execute_disposition(reason, state)
    end
  end

  @impl DBConnection
  def handle_deallocate(_query, %{stmt: stmt}, _opts, state) when is_reference(stmt) do
    Nif.stmt_close(stmt)
    {:ok, nil, state}
  end

  def handle_deallocate(_query, _cursor, _opts, state) do
    {:ok, nil, state}
  end

  # Map an ODPI-C failure on a query/execute path to the right DBConnection reply.
  #
  # A plain SQL error (unique violation, bad column, ...) must keep the pooled
  # connection. We only escalate to {:disconnect, ...} when the connection is
  # actually unusable. ODPI-C's `recoverable` flag is authoritative ONLY on
  # Oracle 12.1+ (it is `false` on older client/server), so we never treat
  # `recoverable: false` alone as fatal -- we confirm with a local, no-round-trip
  # health check before tearing the connection down.
  defp execute_disposition(reason, %__MODULE__{conn: conn} = state) do
    error = Error.from_odpi(reason)

    cond do
      error.recoverable == true ->
        # Oracle explicitly reports the session survived -> keep it.
        {:error, error, state}

      connection_dead?(conn) ->
        {:disconnect, error, state}

      true ->
        {:error, error, state}
    end
  end

  # Local health check (no server round-trip). Treats an errored probe as dead so
  # a connection we can no longer even query is removed from the pool.
  defp connection_dead?(conn) do
    case Nif.conn_get_is_healthy(conn) do
      {:ok, healthy} -> not healthy
      {:error, _} -> true
    end
  end

  defp configure_cursor(stmt, opts) do
    fetch_array_size = Keyword.get(opts, :fetch_array_size, 100)
    prefetch_rows = Keyword.get(opts, :prefetch_rows, 2)

    with :ok <- Nif.stmt_set_fetch_array_size(stmt, fetch_array_size),
         :ok <- Nif.stmt_set_prefetch_rows(stmt, prefetch_rows) do
      :ok
    end
  end

  defp fetch_cursor_rows(stmt, num_columns, columns, rows_to_fetch) do
    for _row_idx <- 1..rows_to_fetch do
      case Nif.stmt_fetch(stmt) do
        {:ok, true} ->
          fetch_row_values(stmt, num_columns, columns)

        {:ok, :done} ->
          nil

        {:error, _} ->
          nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  # ============================================================
  # Query Execution Helpers
  # ============================================================

  defp bind_params(_stmt, []), do: :ok
  defp bind_params(_stmt, params) when params == %{}, do: :ok

  # Positional binding (list of values)
  defp bind_params(stmt, params) when is_list(params) do
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

  # Named binding (map of name => value)
  defp bind_params(stmt, params) when is_map(params) do
    Enum.reduce_while(params, :ok, fn {name, value}, :ok ->
      # Oracle bind names are case-insensitive but ODPI-C returns them uppercase
      name_str = name |> to_string() |> String.upcase()
      type_hint = Type.type_hint(value)
      encoded_value = Type.encode(value)

      case Nif.stmt_bind_value_by_name(stmt, name_str, type_hint, encoded_value) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp execute_select(%Query{statement: stmt, sql: sql}, num_columns, state) do
    # Get column metadata
    columns =
      for pos <- 1..num_columns do
        case Nif.stmt_get_query_info(stmt, pos) do
          {:ok, info} -> info
          {:error, _} -> %{name: "col_#{pos}"}
        end
      end

    # Define NUMBER columns to be fetched as bytes for precision
    define_number_columns_as_bytes(stmt, columns)

    column_names = Enum.map(columns, & &1[:name])

    # Fetch all rows
    rows = fetch_all_rows(stmt, num_columns, columns)

    result = Result.new_select(column_names, rows)
    {:ok, %Query{statement: stmt, sql: sql}, result, state}
  end

  defp execute_dml(stmt, sql, state) do
    case Nif.stmt_get_row_count(stmt) do
      {:ok, count} ->
        result = Result.new_dml(count)
        {:ok, %Query{statement: stmt, sql: sql}, result, state}

      {:error, reason} ->
        execute_disposition(reason, state)
    end
  end

  # Execute DML with RETURNING INTO clause using Variable API
  defp execute_with_returning(
         %Query{statement: stmt, returning: %{columns: columns, start_pos: start_pos}} = query,
         params,
         %__MODULE__{conn: conn} = state
       ) do
    # Create input variables and bind input parameters
    input_vars = create_input_variables(conn, params)

    case bind_input_variables(stmt, input_vars) do
      :ok ->
        # Create output variables for RETURNING columns
        output_vars = create_output_variables(conn, columns)

        case bind_output_variables(stmt, output_vars, start_pos) do
          :ok ->
            # Execute the statement
            case Nif.stmt_execute(stmt) do
              {:ok, _num_columns} ->
                # Get row count
                {:ok, row_count} = Nif.stmt_get_row_count(stmt)

                # Retrieve returned values
                returned_values = retrieve_returned_values(output_vars)

                # Clean up variables
                cleanup_variables(input_vars ++ output_vars)

                # Build result with returned values
                # Ecto expects rows as [[val1, val2, ...]] format
                column_names = Enum.map(columns, fn {name, _type} -> Atom.to_string(name) end)
                rows = if returned_values == [], do: [], else: [returned_values]

                result = Result.new_dml_returning(row_count, column_names, rows)
                {:ok, query, result, state}

              {:error, reason} ->
                cleanup_variables(input_vars ++ output_vars)
                execute_disposition(reason, state)
            end

          {:error, reason} ->
            cleanup_variables(input_vars ++ output_vars)
            execute_disposition(reason, state)
        end

      {:error, reason} ->
        cleanup_variables(input_vars)
        execute_disposition(reason, state)
    end
  end

  # Create input variables for parameters using Variable API
  defp create_input_variables(conn, params) when is_list(params) do
    params
    |> Enum.with_index(1)
    |> Enum.map(fn {value, pos} ->
      {oracle_type, native_type, size} = odpi_types_for_value(value)
      {:ok, var} = Nif.conn_new_var(conn, oracle_type, native_type, 1, size)
      set_variable_value(var, value)
      :ok = Nif.var_set_num_elements(var, 1)
      {pos, var}
    end)
  end

  defp create_input_variables(_conn, _params), do: []

  # Create output variables for RETURNING columns
  defp create_output_variables(conn, columns) do
    Enum.map(columns, fn {_name, type} ->
      {oracle_type, native_type, size} = odpi_types_for_ecto_type(type)
      {:ok, var} = Nif.conn_new_var(conn, oracle_type, native_type, 1, size)
      :ok = Nif.var_set_num_elements(var, 1)
      var
    end)
  end

  # Bind input variables to statement positions
  defp bind_input_variables(stmt, vars) do
    Enum.reduce_while(vars, :ok, fn {pos, var}, :ok ->
      case Nif.stmt_bind_by_pos(stmt, pos, var) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Bind output variables to RETURNING INTO positions
  defp bind_output_variables(stmt, vars, start_pos) do
    vars
    |> Enum.with_index(start_pos)
    |> Enum.reduce_while(:ok, fn {var, pos}, :ok ->
      case Nif.stmt_bind_by_pos(stmt, pos, var) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Retrieve values from output variables
  defp retrieve_returned_values(vars) do
    Enum.flat_map(vars, fn var ->
      case Nif.var_get_returned_data(var, 0) do
        {:ok, values} -> values
        {:error, _} -> []
      end
    end)
  end

  # Clean up variables
  defp cleanup_variables(vars) do
    Enum.each(vars, fn
      {_pos, var} -> Nif.var_release(var)
      var -> Nif.var_release(var)
    end)
  end

  # Set value on a variable based on its type
  defp set_variable_value(_var, nil), do: :ok

  defp set_variable_value(var, value) when is_integer(value) do
    Nif.var_set_from_int(var, 0, value)
  end

  defp set_variable_value(var, value) when is_float(value) do
    Nif.var_set_from_double(var, 0, value)
  end

  defp set_variable_value(var, value) when is_binary(value) do
    Nif.var_set_from_bytes(var, 0, value)
  end

  defp set_variable_value(var, true), do: Nif.var_set_from_int(var, 0, 1)
  defp set_variable_value(var, false), do: Nif.var_set_from_int(var, 0, 0)

  defp set_variable_value(var, %Decimal{} = d) do
    Nif.var_set_from_bytes(var, 0, Decimal.to_string(d))
  end

  defp set_variable_value(var, %Date{} = d) do
    Nif.var_set_from_bytes(var, 0, Date.to_iso8601(d))
  end

  defp set_variable_value(var, %NaiveDateTime{} = ndt) do
    Nif.var_set_from_bytes(var, 0, NaiveDateTime.to_iso8601(ndt))
  end

  defp set_variable_value(var, value) do
    Nif.var_set_from_bytes(var, 0, to_string(value))
  end

  # Map Elixir values to ODPI-C types: {oracle_type, native_type, buffer_size}
  defp odpi_types_for_value(nil), do: {:number, :int64, 0}
  defp odpi_types_for_value(v) when is_integer(v), do: {:number, :int64, 0}
  defp odpi_types_for_value(v) when is_float(v), do: {:number, :double, 0}
  defp odpi_types_for_value(true), do: {:number, :int64, 0}
  defp odpi_types_for_value(false), do: {:number, :int64, 0}
  defp odpi_types_for_value(v) when is_binary(v), do: {:varchar, :bytes, max(byte_size(v), 100)}
  defp odpi_types_for_value(%Decimal{}), do: {:varchar, :bytes, 128}
  defp odpi_types_for_value(%Date{}), do: {:varchar, :bytes, 32}
  defp odpi_types_for_value(%NaiveDateTime{}), do: {:varchar, :bytes, 64}
  defp odpi_types_for_value(_), do: {:varchar, :bytes, 256}

  # Map Ecto types to ODPI-C types for RETURNING columns
  defp odpi_types_for_ecto_type(:id), do: {:number, :int64, 0}
  defp odpi_types_for_ecto_type(:integer), do: {:number, :int64, 0}
  defp odpi_types_for_ecto_type(:bigint), do: {:number, :int64, 0}
  defp odpi_types_for_ecto_type(:string), do: {:varchar, :bytes, 4000}
  defp odpi_types_for_ecto_type(:binary_id), do: {:raw, :bytes, 16}
  defp odpi_types_for_ecto_type(:uuid), do: {:raw, :bytes, 16}
  defp odpi_types_for_ecto_type(_), do: {:varchar, :bytes, 4000}

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

  # Oracle NUMBER type constant from dpi.h
  @oracle_type_number 2010

  # Define NUMBER columns to be fetched as bytes (strings) to preserve full precision.
  # Without this, ODPI-C may return large numbers as doubles, losing precision.
  defp define_number_columns_as_bytes(stmt, columns) do
    columns
    |> Enum.with_index(1)
    |> Enum.each(fn {col, pos} ->
      if col[:oracle_type] == @oracle_type_number do
        # 128 bytes is enough for Oracle NUMBER(38) with sign and decimal point
        Nif.stmt_define_as_bytes(stmt, pos, 128)
      end
    end)
  end

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
