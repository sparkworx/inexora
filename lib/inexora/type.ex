defmodule Inexora.Type do
  @moduledoc """
  Data type conversion between Elixir and Oracle types.

  Handles converting values returned from Oracle to Elixir types,
  and determining the appropriate type hint for parameter binding.
  """

  # Oracle type numbers (from dpi.h)
  @oracle_type_varchar 2001
  @oracle_type_nvarchar 2002
  @oracle_type_char 2003
  @oracle_type_nchar 2004
  @oracle_type_number 2010
  @oracle_type_date 2011
  @oracle_type_timestamp 2012
  @oracle_type_timestamp_tz 2013
  @oracle_type_timestamp_ltz 2014
  @oracle_type_clob 2017
  @oracle_type_blob 2019
  @oracle_type_raw 2006
  @oracle_type_long_raw 2025
  @oracle_type_binary_float 2007
  @oracle_type_binary_double 2008
  @oracle_type_rowid 2005
  @oracle_type_boolean 2022
  @oracle_type_interval_ds 2015
  @oracle_type_interval_ym 2016

  @doc """
  Converts a value from the NIF to an Elixir-friendly format.

  The NIF already does basic conversion, but this handles additional
  transformations like timestamp tuples to DateTime structs.
  """
  @spec to_elixir(term(), map()) :: term()
  def to_elixir(nil, _column_info), do: nil

  def to_elixir(value, %{oracle_type: oracle_type}) do
    convert_from_oracle(value, oracle_type)
  end

  def to_elixir(value, _column_info), do: value

  defp convert_from_oracle(value, @oracle_type_number) when is_binary(value) do
    # NUMBER columns are now fetched as bytes (string) for precision
    # Convert to Decimal for arbitrary precision arithmetic
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      {decimal, _remainder} -> decimal
      :error -> value
    end
  end

  defp convert_from_oracle(value, @oracle_type_number) when is_integer(value) do
    # Integer values can stay as integers
    value
  end

  defp convert_from_oracle(value, @oracle_type_number) when is_float(value) do
    # Float values should be converted to Decimal for consistency
    Decimal.from_float(value)
  end

  defp convert_from_oracle(value, oracle_type)
       when oracle_type in [@oracle_type_date] do
    case value do
      {year, month, day, _hour, _minute, _second, _fsecond} ->
        Date.new!(year, month, day)

      _ ->
        value
    end
  end

  defp convert_from_oracle(value, oracle_type)
       when oracle_type in [
              @oracle_type_timestamp,
              @oracle_type_timestamp_tz,
              @oracle_type_timestamp_ltz
            ] do
    case value do
      {year, month, day, hour, minute, second, fsecond} ->
        microsecond = div(fsecond, 1000)
        NaiveDateTime.new!(year, month, day, hour, minute, second, {microsecond, 6})

      _ ->
        value
    end
  end

  defp convert_from_oracle(value, oracle_type)
       when oracle_type in [@oracle_type_binary_float, @oracle_type_binary_double] do
    # BINARY_FLOAT and BINARY_DOUBLE are returned as strings from NIF
    # Convert to Elixir float
    case value do
      v when is_binary(v) ->
        case Float.parse(v) do
          {float, ""} -> float
          {float, _} -> float
          :error -> value
        end

      v when is_float(v) ->
        v

      _ ->
        value
    end
  end

  defp convert_from_oracle(value, @oracle_type_interval_ds) do
    # INTERVAL DAY TO SECOND comes as {:interval_ds, days, hours, minutes, seconds, fseconds}
    value
  end

  defp convert_from_oracle(value, @oracle_type_interval_ym) do
    # INTERVAL YEAR TO MONTH comes as {:interval_ym, years, months}
    value
  end

  defp convert_from_oracle(value, _oracle_type), do: value

  @doc """
  Determines the type hint atom for binding a value.

  For RAW binary data, use the tuple `{:raw, binary}` to ensure proper
  binding to Oracle RAW/LONG RAW columns.
  """
  @spec type_hint(term()) :: atom()
  def type_hint(nil), do: :integer
  def type_hint({:raw, _}), do: :raw
  def type_hint({:interval_ds, _d, _h, _m, _s, _fs}), do: :interval_ds
  def type_hint({:interval_ym, _y, _m}), do: :interval_ym
  def type_hint(value) when is_boolean(value), do: :integer
  def type_hint(value) when is_integer(value), do: :integer
  def type_hint(value) when is_float(value), do: :float
  def type_hint(value) when is_binary(value), do: :string
  def type_hint(%Decimal{}), do: :string
  def type_hint(%Date{}), do: :string
  def type_hint(%DateTime{}), do: :string
  def type_hint(%NaiveDateTime{}), do: :string
  def type_hint(_), do: :string

  @doc """
  Encodes an Elixir value for binding to Oracle.
  """
  @spec encode(term()) :: term()
  def encode(nil), do: nil
  def encode(true), do: 1
  def encode(false), do: 0
  def encode({:raw, binary}) when is_binary(binary), do: binary
  def encode({:raw, nil}), do: nil
  def encode({:raw, :null}), do: nil
  def encode({:interval_ds, d, h, m, s, fs}), do: {d, h, m, s, fs}
  def encode({:interval_ym, y, m}), do: {y, m}
  def encode(value) when is_integer(value), do: value
  def encode(value) when is_float(value), do: value
  def encode(value) when is_binary(value), do: value
  def encode(%Decimal{} = d), do: Decimal.to_string(d)
  def encode(%Date{} = d), do: Date.to_iso8601(d)
  def encode(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def encode(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  def encode(value), do: to_string(value)

  @doc """
  Returns true if the Oracle type represents a string/character type.
  """
  @spec string_type?(non_neg_integer()) :: boolean()
  def string_type?(oracle_type) do
    oracle_type in [
      @oracle_type_varchar,
      @oracle_type_nvarchar,
      @oracle_type_char,
      @oracle_type_nchar,
      @oracle_type_clob
    ]
  end

  @doc """
  Returns true if the Oracle type represents a numeric type.
  """
  @spec numeric_type?(non_neg_integer()) :: boolean()
  def numeric_type?(oracle_type) do
    oracle_type == @oracle_type_number
  end

  @doc """
  Returns true if the Oracle type represents a date/time type.
  """
  @spec datetime_type?(non_neg_integer()) :: boolean()
  def datetime_type?(oracle_type) do
    oracle_type in [
      @oracle_type_date,
      @oracle_type_timestamp,
      @oracle_type_timestamp_tz,
      @oracle_type_timestamp_ltz
    ]
  end

  @doc """
  Returns true if the Oracle type represents a binary/raw type.
  """
  @spec binary_type?(non_neg_integer()) :: boolean()
  def binary_type?(oracle_type) do
    oracle_type in [
      @oracle_type_raw,
      @oracle_type_long_raw,
      @oracle_type_blob
    ]
  end

  @doc """
  Returns true if the Oracle type represents a floating-point type.
  """
  @spec float_type?(non_neg_integer()) :: boolean()
  def float_type?(oracle_type) do
    oracle_type in [
      @oracle_type_binary_float,
      @oracle_type_binary_double
    ]
  end

  @doc """
  Returns true if the Oracle type represents an interval type.
  """
  @spec interval_type?(non_neg_integer()) :: boolean()
  def interval_type?(oracle_type) do
    oracle_type in [
      @oracle_type_interval_ds,
      @oracle_type_interval_ym
    ]
  end
end
