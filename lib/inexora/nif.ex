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
  Binds a value to a named parameter.

  ## Parameters

    * `stmt` - Statement reference
    * `name` - Parameter name (binary, uppercase)
    * `type` - Type hint atom: `:integer`, `:float`, `:string`, `:binary`, `:raw`, `:interval_ds`, `:interval_ym`
    * `value` - The value to bind (or `nil` for NULL)

  ## Example

      # For SQL: "SELECT :USERNAME FROM dual"
      Nif.stmt_bind_value_by_name(stmt, "USERNAME", :string, "john")
  """
  @spec stmt_bind_value_by_name(stmt(), binary(), atom(), term()) :: :ok | {:error, reason()}
  def stmt_bind_value_by_name(_stmt, _name, _type, _value), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the bind variable names from a prepared statement.

  Returns a list of bind variable names (as uppercase binaries).
  Useful for introspection and named parameter binding.

  ## Example

      # For SQL: "SELECT :username, :age FROM dual"
      {:ok, names} = Nif.stmt_get_bind_names(stmt)
      # names => ["USERNAME", "AGE"]
  """
  @spec stmt_get_bind_names(stmt()) :: {:ok, [binary()]} | {:error, reason()}
  def stmt_get_bind_names(_stmt), do: :erlang.nif_error(:not_loaded)

  @doc """
  Closes and releases a prepared statement.
  """
  @spec stmt_close(stmt()) :: :ok | {:error, reason()}
  def stmt_close(_stmt), do: :erlang.nif_error(:not_loaded)

  @doc """
  Defines a column to be fetched as bytes (string) instead of native type.

  This is used for NUMBER columns to preserve decimal precision.
  Must be called after execute but before fetching rows.

  ## Parameters

    * `stmt` - Statement reference
    * `pos` - Column position (1-based)
    * `max_size` - Maximum size of the string representation
  """
  @spec stmt_define_as_bytes(stmt(), pos_integer(), pos_integer()) :: :ok | {:error, reason()}
  def stmt_define_as_bytes(_stmt, _pos, _max_size), do: :erlang.nif_error(:not_loaded)

  # ============================================================
  # Variable Functions (for batch/array operations)
  # ============================================================

  @type variable :: reference()
  @type oracle_type ::
          :varchar
          | :nvarchar
          | :char
          | :nchar
          | :number
          | :native_int
          | :native_uint
          | :native_float
          | :native_double
          | :date
          | :timestamp
          | :timestamp_tz
          | :timestamp_ltz
          | :raw
          | :long_raw
          | :clob
          | :nclob
          | :blob
          | :rowid
          | :interval_ds
          | :interval_ym
  @type native_type ::
          :bytes | :int64 | :uint64 | :float | :double | :timestamp | :interval_ds | :interval_ym | :lob | :rowid

  @doc """
  Creates a new variable for array/batch operations.

  ## Parameters

    * `conn` - Connection reference
    * `oracle_type` - Oracle data type atom (:varchar, :number, :raw, etc.)
    * `native_type` - Native data type atom (:bytes, :int64, :double, etc.)
    * `max_array_size` - Maximum number of elements in the array
    * `size` - Size per element (for bytes/string types)

  ## Example

      # Create a variable for 10 string values, each up to 100 chars
      {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 10, 100)

      # Create a variable for 10 integer values
      {:ok, var} = Nif.conn_new_var(conn, :number, :int64, 10, 0)
  """
  @spec conn_new_var(conn(), oracle_type(), native_type(), pos_integer(), non_neg_integer()) ::
          {:ok, variable()} | {:error, reason()}
  def conn_new_var(_conn, _oracle_type, _native_type, _max_array_size, _size),
    do: :erlang.nif_error(:not_loaded)

  @doc """
  Sets the number of active elements in the array.

  Call this before executing to specify how many array elements to process.

  ## Example

      :ok = Nif.var_set_num_elements(var, 5)  # Process 5 elements
  """
  @spec var_set_num_elements(variable(), non_neg_integer()) :: :ok | {:error, reason()}
  def var_set_num_elements(_var, _num_elements), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the number of active elements in the array.

  After execution, this may reflect the actual number of elements populated.
  """
  @spec var_get_num_elements(variable()) :: {:ok, non_neg_integer()} | {:error, reason()}
  def var_get_num_elements(_var), do: :erlang.nif_error(:not_loaded)

  @doc """
  Sets a bytes/string value at the given array position (0-indexed).

  ## Example

      :ok = Nif.var_set_from_bytes(var, 0, "first_value")
      :ok = Nif.var_set_from_bytes(var, 1, "second_value")
  """
  @spec var_set_from_bytes(variable(), non_neg_integer(), binary()) :: :ok | {:error, reason()}
  def var_set_from_bytes(_var, _pos, _value), do: :erlang.nif_error(:not_loaded)

  @doc """
  Sets an integer value at the given array position (0-indexed).

  ## Example

      :ok = Nif.var_set_from_int(var, 0, 100)
      :ok = Nif.var_set_from_int(var, 1, 200)
  """
  @spec var_set_from_int(variable(), non_neg_integer(), integer()) :: :ok | {:error, reason()}
  def var_set_from_int(_var, _pos, _value), do: :erlang.nif_error(:not_loaded)

  @doc """
  Sets a double/float value at the given array position (0-indexed).

  ## Example

      :ok = Nif.var_set_from_double(var, 0, 3.14)
      :ok = Nif.var_set_from_double(var, 1, 2.71)
  """
  @spec var_set_from_double(variable(), non_neg_integer(), number()) :: :ok | {:error, reason()}
  def var_set_from_double(_var, _pos, _value), do: :erlang.nif_error(:not_loaded)

  @doc """
  Sets NULL at the given array position (0-indexed).

  ## Example

      :ok = Nif.var_set_null(var, 2)  # Set position 2 to NULL
  """
  @spec var_set_null(variable(), non_neg_integer()) :: :ok | {:error, reason()}
  def var_set_null(_var, _pos), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the returned data from a RETURNING INTO clause.

  After executing a DML statement with RETURNING INTO, call this to retrieve
  the returned values.

  ## Parameters

    * `var` - Variable reference (must be bound to a RETURNING clause)
    * `pos` - Array position (typically 0 for single-row operations)

  ## Returns

    `{:ok, [values]}` - List of returned values

  ## Example

      # After INSERT ... RETURNING id INTO :id_var
      {:ok, [returned_id]} = Nif.var_get_returned_data(id_var, 0)
  """
  @spec var_get_returned_data(variable(), non_neg_integer()) :: {:ok, list()} | {:error, reason()}
  def var_get_returned_data(_var, _pos), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the value at the given array position (0-indexed).

  Useful for reading back OUT parameter values after execution.
  """
  @spec var_get_value(variable(), non_neg_integer()) :: {:ok, term()} | {:error, reason()}
  def var_get_value(_var, _pos), do: :erlang.nif_error(:not_loaded)

  @doc """
  Releases a variable.

  The variable will also be released when garbage collected, but this
  can be called to release immediately.
  """
  @spec var_release(variable()) :: :ok | {:error, reason()}
  def var_release(_var), do: :erlang.nif_error(:not_loaded)

  @doc """
  Binds a variable by position.

  Unlike `stmt_bind_value_by_pos`, this binds a variable reference which can
  hold multiple values for batch operations.

  ## Example

      :ok = Nif.stmt_bind_by_pos(stmt, 1, var)
  """
  @spec stmt_bind_by_pos(stmt(), pos_integer(), variable()) :: :ok | {:error, reason()}
  def stmt_bind_by_pos(_stmt, _pos, _var), do: :erlang.nif_error(:not_loaded)

  @doc """
  Binds a variable by name.

  Unlike `stmt_bind_value_by_name`, this binds a variable reference which can
  hold multiple values for batch operations.

  ## Example

      :ok = Nif.stmt_bind_by_name(stmt, "NAME", var)
  """
  @spec stmt_bind_by_name(stmt(), binary(), variable()) :: :ok | {:error, reason()}
  def stmt_bind_by_name(_stmt, _name, _var), do: :erlang.nif_error(:not_loaded)

  @doc """
  Executes a statement multiple times (batch/array DML).

  ## Parameters

    * `stmt` - Statement reference
    * `num_iters` - Number of iterations to execute (must match array sizes)

  ## Returns

    `{:ok, num_columns}` - Number of query columns (0 for DML)

  ## Example

      # After binding arrays with 5 elements each
      {:ok, 0} = Nif.stmt_execute_many(stmt, 5)
  """
  @spec stmt_execute_many(stmt(), pos_integer()) :: {:ok, non_neg_integer()} | {:error, reason()}
  def stmt_execute_many(_stmt, _num_iters), do: :erlang.nif_error(:not_loaded)

  # ============================================================
  # Cursor/Streaming Functions
  # ============================================================

  @doc """
  Fetches multiple rows at once (batch fetch).

  More efficient than row-by-row fetching for large result sets.

  ## Parameters

    * `stmt` - Statement reference (after execute)
    * `max_rows` - Maximum number of rows to fetch in this batch

  ## Returns

    `{:ok, {rows_fetched, buffer_row_index, more_rows}}` where:
    - `rows_fetched` - Actual number of rows fetched (0-based count)
    - `buffer_row_index` - Starting index in the internal buffer
    - `more_rows` - `true` if more rows available, `false` if at end

  ## Example

      {:ok, num_cols} = Nif.stmt_execute(stmt)
      {:ok, {count, start_idx, more?}} = Nif.stmt_fetch_rows(stmt, 100)
      # Fetch values for rows start_idx to start_idx + count - 1
  """
  @spec stmt_fetch_rows(stmt(), pos_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), boolean()}} | {:error, reason()}
  def stmt_fetch_rows(_stmt, _max_rows), do: :erlang.nif_error(:not_loaded)

  @doc """
  Sets the internal array size used for fetching.

  This controls how many rows are fetched from the database in each round-trip.
  Larger values use more memory but reduce network overhead for large result sets.

  ## Parameters

    * `stmt` - Statement reference
    * `size` - Array size (default is typically 100)

  ## Example

      :ok = Nif.stmt_set_fetch_array_size(stmt, 1000)  # Fetch 1000 rows per batch
  """
  @spec stmt_set_fetch_array_size(stmt(), pos_integer()) :: :ok | {:error, reason()}
  def stmt_set_fetch_array_size(_stmt, _size), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the current internal array size used for fetching.

  ## Returns

    `{:ok, size}` - Current array size
  """
  @spec stmt_get_fetch_array_size(stmt()) :: {:ok, non_neg_integer()} | {:error, reason()}
  def stmt_get_fetch_array_size(_stmt), do: :erlang.nif_error(:not_loaded)

  @doc """
  Sets the number of rows to prefetch from the Oracle client library.

  This is a separate setting from the fetch array size. Prefetch controls
  how many rows the Oracle client library fetches ahead.

  ## Parameters

    * `stmt` - Statement reference
    * `num_rows` - Number of rows to prefetch (0 to disable)
  """
  @spec stmt_set_prefetch_rows(stmt(), non_neg_integer()) :: :ok | {:error, reason()}
  def stmt_set_prefetch_rows(_stmt, _num_rows), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the current number of rows being prefetched.

  ## Returns

    `{:ok, num_rows}` - Current prefetch setting
  """
  @spec stmt_get_prefetch_rows(stmt()) :: {:ok, non_neg_integer()} | {:error, reason()}
  def stmt_get_prefetch_rows(_stmt), do: :erlang.nif_error(:not_loaded)

end
