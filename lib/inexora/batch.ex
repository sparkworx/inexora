defmodule Inexora.Batch do
  @moduledoc """
  High-level batch operations for Oracle database.

  This module provides convenient functions for batch DML operations
  using the Variable API. It supports:

  - Batch INSERT with RETURNING INTO for auto-generated IDs
  - Batch UPDATE with RETURNING
  - Batch DELETE with RETURNING

  ## Example

      # Batch insert with returning
      {:ok, returned_ids} = Batch.insert(conn,
        "INSERT INTO users (name, email) VALUES (:1, :2) RETURNING id INTO :3",
        [
          ["Alice", "alice@example.com"],
          ["Bob", "bob@example.com"],
          ["Charlie", "charlie@example.com"]
        ],
        returning: [type: :number, native: :int64]
      )

  """

  alias Inexora.Nif

  @doc """
  Executes a batch INSERT with RETURNING INTO support.

  ## Parameters

    * `conn` - The connection reference
    * `sql` - SQL statement with RETURNING INTO clause
    * `rows` - List of rows, each row is a list of values
    * `opts` - Options:
      * `:returning` - Specification for RETURNING INTO columns:
        * Single column: `[type: :number, native: :int64]`
        * Multiple columns: `[[type: :number, native: :int64], [type: :varchar, native: :bytes, size: 100]]`

  ## Returns

    * `{:ok, returned_values}` - List of returned values for each row
    * `{:error, reason}` - Error tuple

  """
  @spec insert(reference(), String.t(), [[term()]], keyword()) ::
          {:ok, [[term()]]} | {:error, term()}
  def insert(conn, sql, rows, opts \\ []) do
    returning_spec = Keyword.get(opts, :returning)
    execute_batch_with_returning(conn, sql, rows, returning_spec)
  end

  @doc """
  Executes a simple batch INSERT without RETURNING.

  ## Parameters

    * `conn` - The connection reference
    * `sql` - SQL statement (single row INSERT)
    * `rows` - List of rows, each row is a list of values

  ## Returns

    * `{:ok, row_count}` - Number of rows inserted
    * `{:error, reason}` - Error tuple

  """
  @spec insert_all(reference(), String.t(), [[term()]]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def insert_all(conn, sql, rows) do
    execute_batch(conn, sql, rows)
  end

  # ============================================================
  # Private Implementation
  # ============================================================

  defp execute_batch_with_returning(conn, sql, rows, nil) do
    # No RETURNING - just execute batch
    execute_batch(conn, sql, rows)
  end

  defp execute_batch_with_returning(conn, sql, rows, returning_spec) do
    num_rows = length(rows)

    if num_rows == 0 do
      {:ok, []}
    else
      # Normalize returning_spec to list of specs
      returning_specs =
        if Keyword.keyword?(returning_spec) do
          [returning_spec]
        else
          returning_spec
        end

      with {:ok, stmt} <- Nif.stmt_prepare(conn, sql),
           {:ok, input_vars} <- create_input_variables(conn, rows),
           {:ok, output_vars} <- create_output_variables(conn, num_rows, returning_specs),
           :ok <- bind_input_variables(stmt, input_vars),
           :ok <- bind_output_variables(stmt, output_vars, length(input_vars)),
           {:ok, _} <- Nif.stmt_execute_many(stmt, num_rows),
           {:ok, returned} <- get_returned_data(output_vars, num_rows) do
        # Cleanup
        Nif.stmt_close(stmt)
        Enum.each(input_vars, &Nif.var_release/1)
        Enum.each(output_vars, &Nif.var_release/1)

        {:ok, returned}
      else
        {:error, _reason} = error ->
          error
      end
    end
  end

  defp execute_batch(conn, sql, rows) do
    num_rows = length(rows)

    if num_rows == 0 do
      {:ok, 0}
    else
      with {:ok, stmt} <- Nif.stmt_prepare(conn, sql),
           {:ok, input_vars} <- create_input_variables(conn, rows),
           :ok <- bind_input_variables(stmt, input_vars),
           {:ok, _} <- Nif.stmt_execute_many(stmt, num_rows) do
        # Cleanup
        Nif.stmt_close(stmt)
        Enum.each(input_vars, &Nif.var_release/1)

        {:ok, num_rows}
      end
    end
  end

  # Create input variables based on the row data
  defp create_input_variables(conn, rows) do
    # Transpose rows to get columns
    # rows = [[a1, b1], [a2, b2], [a3, b3]]
    # columns = [[a1, a2, a3], [b1, b2, b3]]
    columns = transpose(rows)
    num_rows = length(rows)

    vars =
      Enum.map(columns, fn column_values ->
        create_column_variable(conn, column_values, num_rows)
      end)

    # Check for errors
    case Enum.find(vars, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(vars, fn {:ok, var} -> var end)}
      error -> error
    end
  end

  defp create_column_variable(conn, column_values, num_rows) do
    # Determine variable type based on the values
    sample_value = Enum.find(column_values, &(&1 != nil))
    {oracle_type, native_type, size} = infer_variable_type(sample_value)

    with {:ok, var} <- Nif.conn_new_var(conn, oracle_type, native_type, num_rows, size) do
      # Set values for each row
      column_values
      |> Enum.with_index()
      |> Enum.each(fn {value, idx} ->
        set_variable_value(var, idx, value, native_type)
      end)

      :ok = Nif.var_set_num_elements(var, num_rows)

      {:ok, var}
    end
  end

  defp create_output_variables(conn, num_rows, returning_specs) do
    vars =
      Enum.map(returning_specs, fn spec ->
        oracle_type = Keyword.fetch!(spec, :type)
        native_type = Keyword.fetch!(spec, :native)
        size = Keyword.get(spec, :size, 0)

        with {:ok, var} <- Nif.conn_new_var(conn, oracle_type, native_type, num_rows, size) do
          :ok = Nif.var_set_num_elements(var, num_rows)
          {:ok, var}
        end
      end)

    case Enum.find(vars, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(vars, fn {:ok, var} -> var end)}
      error -> error
    end
  end

  defp bind_input_variables(stmt, vars) do
    vars
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {var, pos}, :ok ->
      case Nif.stmt_bind_by_pos(stmt, pos, var) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp bind_output_variables(stmt, vars, offset) do
    vars
    |> Enum.with_index(offset + 1)
    |> Enum.reduce_while(:ok, fn {var, pos}, :ok ->
      case Nif.stmt_bind_by_pos(stmt, pos, var) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp get_returned_data(output_vars, num_rows) do
    # For each row, get the returned values from all output vars
    returned =
      for row_idx <- 0..(num_rows - 1) do
        for var <- output_vars do
          case Nif.var_get_returned_data(var, row_idx) do
            {:ok, [value]} -> value
            {:ok, values} -> values
            {:error, _} -> nil
          end
        end
      end

    {:ok, returned}
  end

  defp set_variable_value(var, idx, nil, _native_type) do
    Nif.var_set_null(var, idx)
  end

  defp set_variable_value(var, idx, value, :int64) do
    encoded = encode_value(value)
    Nif.var_set_from_int(var, idx, encoded)
  end

  defp set_variable_value(var, idx, value, :double) do
    encoded = encode_value(value)
    Nif.var_set_from_double(var, idx, encoded)
  end

  defp set_variable_value(var, idx, value, :bytes) do
    encoded = encode_value(value)
    encoded_str = if is_binary(encoded), do: encoded, else: to_string(encoded)
    Nif.var_set_from_bytes(var, idx, encoded_str)
  end

  defp set_variable_value(var, idx, value, _native_type) do
    encoded = encode_value(value)
    encoded_str = if is_binary(encoded), do: encoded, else: to_string(encoded)
    Nif.var_set_from_bytes(var, idx, encoded_str)
  end

  defp encode_value(true), do: 1
  defp encode_value(false), do: 0
  defp encode_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp encode_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp encode_value(value), do: value

  defp infer_variable_type(nil), do: {:varchar, :bytes, 4000}
  defp infer_variable_type(value) when is_integer(value), do: {:number, :int64, 0}
  defp infer_variable_type(value) when is_float(value), do: {:native_double, :double, 0}
  defp infer_variable_type(value) when is_boolean(value), do: {:number, :int64, 0}
  defp infer_variable_type(value) when is_binary(value), do: {:varchar, :bytes, max(byte_size(value) * 2, 4000)}
  defp infer_variable_type(%Decimal{}), do: {:varchar, :bytes, 100}
  defp infer_variable_type(%Date{}), do: {:varchar, :bytes, 32}
  defp infer_variable_type(%DateTime{}), do: {:varchar, :bytes, 64}
  defp infer_variable_type(%NaiveDateTime{}), do: {:varchar, :bytes, 64}
  defp infer_variable_type(_), do: {:varchar, :bytes, 4000}

  defp transpose([]), do: []
  defp transpose([[] | _]), do: []
  defp transpose(rows) do
    [Enum.map(rows, &hd/1) | transpose(Enum.map(rows, &tl/1))]
  end
end
