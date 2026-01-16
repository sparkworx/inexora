defmodule Inexora.Result do
  @moduledoc """
  Represents the result of a SQL query execution.

  ## Fields

    * `:columns` - List of column names (for SELECT queries)
    * `:rows` - List of rows, where each row is a list of values
    * `:num_rows` - Number of rows returned (SELECT) or affected (DML)
  """

  defstruct [:columns, :rows, :num_rows]

  @type t :: %__MODULE__{
          columns: [String.t()] | nil,
          rows: [[term()]] | nil,
          num_rows: non_neg_integer()
        }

  @doc """
  Creates a new Result for a SELECT query.
  """
  @spec new_select([String.t()], [[term()]]) :: t()
  def new_select(columns, rows) do
    %__MODULE__{
      columns: columns,
      rows: rows,
      num_rows: length(rows)
    }
  end

  @doc """
  Creates a new Result for a DML statement (INSERT/UPDATE/DELETE).
  """
  @spec new_dml(non_neg_integer()) :: t()
  def new_dml(affected_rows) do
    %__MODULE__{
      columns: nil,
      rows: nil,
      num_rows: affected_rows
    }
  end
end
