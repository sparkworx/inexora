defmodule Inexora.Query do
  @moduledoc """
  Represents a prepared SQL query for Oracle database.

  This struct implements the `DBConnection.Query` protocol.

  ## Public interface (frozen contract)

  `new/2` is the **only** public way to build a query. The struct's fields are
  internal to the driver — external callers (notably the `ecto_oracle` adapter)
  must not construct `%Inexora.Query{}` literals or read its fields directly.
  Only the `returning` shape passed into `new/2` is part of the contract:

      %{columns: [{atom(), returning_type()}], start_pos: pos_integer()}

  See `docs/adapter-split-plan.md` for the full frozen driver interface.
  """

  defstruct [:statement, :sql, :num_columns, :columns, :returning]

  @typedoc """
  Per-column type carried in a `returning` spec. Currently always `:id`
  (see the `{col, :id}` limitation in the adapter-split plan); typed as an atom
  so a later type-carrying fix does not change the frozen `returning` shape.
  """
  @type returning_type :: atom()

  @type returning_spec :: %{
          columns: [{atom(), returning_type()}],
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
  Builds a query from a SQL string and an optional `returning` spec.

  This is the sole public constructor for `%Inexora.Query{}`. Pass `returning`
  to carry RETURNING INTO column/position metadata (see `t:returning_spec/0`);
  omit it for ordinary queries.
  """
  @spec new(String.t(), returning_spec() | nil) :: t()
  def new(sql, returning \\ nil) when is_binary(sql) do
    %__MODULE__{sql: sql, returning: returning}
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
