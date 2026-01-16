defmodule Inexora.Cursor do
  @moduledoc """
  Cursor for streaming large result sets from Oracle.

  This module provides efficient streaming of query results by fetching
  rows in batches, reducing memory usage for large result sets.

  ## Example

      # Stream with default batch size (100 rows)
      {:ok, conn} = DBConnection.start_link(Inexora.Connection, opts)
      query = Inexora.Query.new("SELECT * FROM large_table")

      Inexora.Cursor.stream(conn, query, [], max_rows: 1000)
      |> Stream.each(fn row -> process(row) end)
      |> Stream.run()

  ## Options

    * `:max_rows` - Maximum rows to fetch per batch (default: 100)
    * `:fetch_array_size` - ODPI-C internal array size (default: 100)
    * `:prefetch_rows` - Oracle client prefetch setting (default: 2)

  """

  alias Inexora.Nif
  alias Inexora.Query
  alias Inexora.Type

  defstruct [:stmt, :columns, :num_columns, :max_rows, :done]

  @type t :: %__MODULE__{
          stmt: reference(),
          columns: [map()],
          num_columns: non_neg_integer(),
          max_rows: pos_integer(),
          done: boolean()
        }

  @default_max_rows 100
  @default_fetch_array_size 100
  @default_prefetch_rows 2

  @doc """
  Creates a stream that yields rows from the query result.

  The stream fetches rows in batches for efficiency while providing
  a simple enumerable interface.

  ## Options

    * `:max_rows` - Maximum rows per batch (default: #{@default_max_rows})
    * `:fetch_array_size` - ODPI-C fetch array size (default: #{@default_fetch_array_size})
    * `:prefetch_rows` - Oracle prefetch rows (default: #{@default_prefetch_rows})

  ## Example

      Inexora.Cursor.stream(conn, query, params)
      |> Enum.take(100)

  """
  @spec stream(DBConnection.conn(), Query.t(), list(), keyword()) :: Enumerable.t()
  def stream(conn, query, params, opts \\ []) do
    Stream.resource(
      fn -> init_stream(conn, query, params, opts) end,
      &fetch_next/1,
      &close/1
    )
  end

  @doc """
  Opens a cursor for the given query.

  This is a lower-level function. For most use cases, prefer `stream/4`.
  """
  @spec open(reference(), Query.t() | String.t(), list(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def open(conn, query_or_sql, params \\ [], opts \\ [])

  def open(conn, sql, params, opts) when is_binary(sql) do
    open(conn, Query.new(sql), params, opts)
  end

  def open(conn, %Query{} = query, params, opts) do
    max_rows = Keyword.get(opts, :max_rows, @default_max_rows)
    fetch_array_size = Keyword.get(opts, :fetch_array_size, @default_fetch_array_size)
    prefetch_rows = Keyword.get(opts, :prefetch_rows, @default_prefetch_rows)

    sql = IO.iodata_to_binary(query.sql)

    with {:ok, stmt} <- Nif.stmt_prepare(conn, sql),
         :ok <- bind_params(stmt, params),
         :ok <- configure_fetch(stmt, fetch_array_size, prefetch_rows),
         {:ok, num_columns} <- Nif.stmt_execute(stmt),
         true <- num_columns > 0 || {:error, "not a query"} do
      columns = get_columns(stmt, num_columns)

      {:ok,
       %__MODULE__{
         stmt: stmt,
         columns: columns,
         num_columns: num_columns,
         max_rows: max_rows,
         done: false
       }}
    else
      {:error, _reason} = error -> error
      false -> {:error, "query returned no columns"}
    end
  end

  @doc """
  Fetches the next batch of rows from the cursor.

  Returns `{:ok, rows, cursor}` where rows is a list of row lists.
  Returns `{:done, cursor}` when there are no more rows.
  """
  @spec fetch(t()) :: {:ok, [[term()]], t()} | {:done, t()} | {:error, term()}
  def fetch(%__MODULE__{done: true} = cursor) do
    {:done, cursor}
  end

  def fetch(%__MODULE__{stmt: stmt, num_columns: num_columns, columns: columns, max_rows: max_rows} = cursor) do
    # Fetch up to max_rows using stmt_fetch in a loop
    {rows, done} = fetch_batch(stmt, num_columns, columns, max_rows, [], false)

    case {rows, done} do
      {[], true} ->
        {:done, %{cursor | done: true}}

      {rows, done} ->
        {:ok, rows, %{cursor | done: done}}
    end
  end

  @doc """
  Closes the cursor and releases resources.
  """
  @spec close(t() | {:ok, t()} | {:error, term()}) :: :ok
  def close(%__MODULE__{stmt: stmt}) when is_reference(stmt) do
    Nif.stmt_close(stmt)
    :ok
  end

  def close({:ok, cursor}), do: close(cursor)
  def close({:error, _}), do: :ok
  def close(_), do: :ok

  # ============================================================
  # Private Functions
  # ============================================================

  defp bind_params(_stmt, []), do: :ok

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

  defp configure_fetch(stmt, array_size, prefetch_rows) do
    with :ok <- Nif.stmt_set_fetch_array_size(stmt, array_size),
         :ok <- Nif.stmt_set_prefetch_rows(stmt, prefetch_rows) do
      :ok
    end
  end

  defp get_columns(stmt, num_columns) do
    for pos <- 1..num_columns do
      case Nif.stmt_get_query_info(stmt, pos) do
        {:ok, info} -> info
        {:error, _} -> %{name: "col_#{pos}"}
      end
    end
  end

  defp fetch_batch(_stmt, _num_columns, _columns, 0, acc, done) do
    {Enum.reverse(acc), done}
  end

  defp fetch_batch(stmt, num_columns, columns, remaining, acc, _done) do
    case Nif.stmt_fetch(stmt) do
      {:ok, true} ->
        row = fetch_row_values(stmt, num_columns, columns)
        fetch_batch(stmt, num_columns, columns, remaining - 1, [row | acc], false)

      {:ok, :done} ->
        {Enum.reverse(acc), true}

      {:error, _} ->
        {Enum.reverse(acc), true}
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

  # Stream.resource callbacks

  defp init_stream(conn, query, params, opts) do
    # This is called with a connection reference
    case open(conn, query, params, opts) do
      {:ok, cursor} -> cursor
      {:error, reason} -> raise "Failed to open cursor: #{inspect(reason)}"
    end
  end

  defp fetch_next(%__MODULE__{done: true} = cursor) do
    {:halt, cursor}
  end

  defp fetch_next(%__MODULE__{} = cursor) do
    case fetch(cursor) do
      {:ok, rows, new_cursor} ->
        {rows, new_cursor}

      {:done, new_cursor} ->
        {:halt, new_cursor}
    end
  end
end
