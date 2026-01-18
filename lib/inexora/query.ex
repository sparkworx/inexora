defmodule Inexora.Query do
  @moduledoc """
  Represents a prepared SQL query for Oracle database.

  This struct implements the `DBConnection.Query` protocol.
  """

  defstruct [:statement, :sql, :num_columns, :columns, :returning]

  @type returning_spec :: %{
          columns: [atom()],
          start_pos: pos_integer()
        }

  @type t :: %__MODULE__{
          statement: reference() | nil,
          sql: String.t(),
          num_columns: non_neg_integer() | nil,
          columns: [map()] | nil,
          returning: returning_spec() | nil
        }

  @doc """
  Creates a new Query struct from a SQL string.
  """
  @spec new(String.t()) :: t()
  def new(sql) when is_binary(sql) do
    %__MODULE__{sql: sql}
  end

  defimpl DBConnection.Query do
    def parse(query, _opts), do: query
    def describe(query, _opts), do: query

    def encode(_query, params, _opts) do
      # Params are passed through - encoding happens at bind time
      params
    end

    def decode(_query, result, _opts) do
      # Result is already decoded by Inexora.Connection
      result
    end
  end

  defimpl String.Chars do
    def to_string(%Inexora.Query{sql: sql}), do: sql
  end
end
