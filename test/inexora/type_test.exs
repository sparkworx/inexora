defmodule Inexora.TypeTest do
  use ExUnit.Case, async: true

  alias Inexora.Type

  describe "type_hint/1" do
    test "returns :integer for nil" do
      assert Type.type_hint(nil) == :integer
    end

    test "returns :integer for integers" do
      assert Type.type_hint(42) == :integer
      assert Type.type_hint(-1) == :integer
      assert Type.type_hint(0) == :integer
    end

    test "returns :float for floats" do
      assert Type.type_hint(3.14) == :float
      assert Type.type_hint(-0.5) == :float
    end

    test "returns :string for binaries" do
      assert Type.type_hint("hello") == :string
      assert Type.type_hint("") == :string
    end

    test "returns :string for Decimal" do
      assert Type.type_hint(Decimal.new("123.45")) == :string
    end

    test "returns :string for Date" do
      assert Type.type_hint(~D[2024-01-15]) == :string
    end

    test "returns :string for DateTime" do
      assert Type.type_hint(~U[2024-01-15 10:30:00Z]) == :string
    end

    test "returns :string for NaiveDateTime" do
      assert Type.type_hint(~N[2024-01-15 10:30:00]) == :string
    end

    test "returns :string for other types" do
      assert Type.type_hint(:atom) == :string
      assert Type.type_hint([1, 2, 3]) == :string
    end
  end

  describe "encode/1" do
    test "returns nil for nil" do
      assert Type.encode(nil) == nil
    end

    test "returns integer as-is" do
      assert Type.encode(42) == 42
      assert Type.encode(-100) == -100
    end

    test "returns float as-is" do
      assert Type.encode(3.14) == 3.14
    end

    test "returns binary as-is" do
      assert Type.encode("hello") == "hello"
    end

    test "converts Decimal to string" do
      decimal = Decimal.new("123.456")
      assert Type.encode(decimal) == "123.456"
    end

    test "converts Date to ISO8601 string" do
      assert Type.encode(~D[2024-01-15]) == "2024-01-15"
    end

    test "converts DateTime to ISO8601 string" do
      result = Type.encode(~U[2024-01-15 10:30:00Z])
      assert result == "2024-01-15T10:30:00Z"
    end

    test "converts NaiveDateTime to ISO8601 string" do
      result = Type.encode(~N[2024-01-15 10:30:00])
      assert result == "2024-01-15T10:30:00"
    end

    test "converts other values to string" do
      assert Type.encode(:atom) == "atom"
    end
  end

  describe "to_elixir/2" do
    test "returns nil unchanged" do
      assert Type.to_elixir(nil, %{}) == nil
    end

    test "returns value unchanged when no oracle_type" do
      assert Type.to_elixir("hello", %{}) == "hello"
      assert Type.to_elixir(42, %{}) == 42
    end

    # Oracle NUMBER type (2010) - Decimal precision tests
    test "converts NUMBER string to Decimal" do
      # NUMBER columns are fetched as bytes (string) for precision
      result = Type.to_elixir("123.456", %{oracle_type: 2010})
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("123.456"))
    end

    test "converts NUMBER string with high precision to Decimal" do
      # Test high precision decimal
      value = "12345678901234567890.12345678901234567890"
      result = Type.to_elixir(value, %{oracle_type: 2010})
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new(value))
    end

    test "converts NUMBER integer string to Decimal" do
      result = Type.to_elixir("42", %{oracle_type: 2010})
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("42"))
    end

    test "converts NUMBER negative string to Decimal" do
      result = Type.to_elixir("-99.99", %{oracle_type: 2010})
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("-99.99"))
    end

    test "keeps NUMBER integer as integer" do
      result = Type.to_elixir(42, %{oracle_type: 2010})
      assert result == 42
    end

    test "converts NUMBER float to Decimal" do
      result = Type.to_elixir(3.14, %{oracle_type: 2010})
      assert %Decimal{} = result
    end

    # Oracle DATE type (2011)
    test "converts DATE tuple to Date" do
      value = {2024, 1, 15, 10, 30, 0, 0}
      result = Type.to_elixir(value, %{oracle_type: 2011})
      assert result == ~D[2024-01-15]
    end

    # Oracle TIMESTAMP type (2012)
    test "converts TIMESTAMP tuple to NaiveDateTime" do
      # fsecond is in nanoseconds, convert to microseconds
      value = {2024, 1, 15, 10, 30, 45, 123_456_000}
      result = Type.to_elixir(value, %{oracle_type: 2012})
      assert result == ~N[2024-01-15 10:30:45.123456]
    end

    # Oracle TIMESTAMP WITH TIME ZONE (2013)
    test "converts TIMESTAMP_TZ tuple to NaiveDateTime" do
      value = {2024, 6, 20, 14, 0, 0, 500_000_000}
      result = Type.to_elixir(value, %{oracle_type: 2013})
      assert result == ~N[2024-06-20 14:00:00.500000]
    end

    test "returns non-tuple timestamp values unchanged" do
      assert Type.to_elixir("2024-01-15", %{oracle_type: 2011}) == "2024-01-15"
    end

    test "returns values with unknown oracle_type unchanged" do
      assert Type.to_elixir("test", %{oracle_type: 9999}) == "test"
    end
  end

  describe "string_type?/1" do
    test "returns true for VARCHAR2 type" do
      assert Type.string_type?(2001) == true
    end

    test "returns true for NVARCHAR2 type" do
      assert Type.string_type?(2002) == true
    end

    test "returns true for CHAR type" do
      assert Type.string_type?(2003) == true
    end

    test "returns true for CLOB type" do
      assert Type.string_type?(2017) == true
    end

    test "returns false for NUMBER type" do
      assert Type.string_type?(2010) == false
    end
  end

  describe "numeric_type?/1" do
    test "returns true for NUMBER type" do
      assert Type.numeric_type?(2010) == true
    end

    test "returns false for VARCHAR2 type" do
      assert Type.numeric_type?(2001) == false
    end
  end

  describe "datetime_type?/1" do
    test "returns true for DATE type" do
      assert Type.datetime_type?(2011) == true
    end

    test "returns true for TIMESTAMP type" do
      assert Type.datetime_type?(2012) == true
    end

    test "returns true for TIMESTAMP_TZ type" do
      assert Type.datetime_type?(2013) == true
    end

    test "returns true for TIMESTAMP_LTZ type" do
      assert Type.datetime_type?(2014) == true
    end

    test "returns false for VARCHAR2 type" do
      assert Type.datetime_type?(2001) == false
    end
  end
end
