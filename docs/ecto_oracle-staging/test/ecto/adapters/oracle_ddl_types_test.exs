defmodule Ecto.Adapters.OracleDDLTypesTest do
  @moduledoc """
  DDL type-mapping tests for the Oracle adapter's `ecto_to_db` map.

  Relocated from the `inexora` driver's per-datatype test files during the
  adapter split — these assert on adapter DDL generation (the adapter-owned
  type-name map, ADR-0001), not on driver value encoding.
  """
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Oracle.Connection, as: SQL

  defp create_ddl(name, columns) do
    table = %Ecto.Migration.Table{name: name}
    [ddl] = SQL.execute_ddl({:create, table, columns})
    IO.iodata_to_binary(ddl)
  end

  describe "Float types in Ecto DDL" do
    test "generates correct DDL for float types" do
      result =
        create_ddl("float_ddl_test", [
          {:add, :id, :bigserial, [primary_key: true]},
          {:add, :float_field, :float, []},
          {:add, :binary_float_field, :binary_float, []},
          {:add, :binary_double_field, :binary_double, []}
        ])

      assert result =~ "CREATE TABLE"
      assert result =~ ~s("FLOAT_DDL_TEST")
      # :float maps to BINARY_DOUBLE by default
      assert result =~ "BINARY_DOUBLE"
      assert result =~ "BINARY_FLOAT"
    end
  end

  describe "INTERVAL types in Ecto DDL" do
    test "generates correct DDL for interval types" do
      result =
        create_ddl("interval_ddl_test", [
          {:add, :id, :bigserial, [primary_key: true]},
          {:add, :duration, :interval_day_to_second, []},
          {:add, :period, :interval_year_to_month, []}
        ])

      assert result =~ "CREATE TABLE"
      assert result =~ ~s("INTERVAL_DDL_TEST")
      assert result =~ "INTERVAL DAY TO SECOND"
      assert result =~ "INTERVAL YEAR TO MONTH"
    end
  end

  describe "RAW in Ecto DDL" do
    test "generates correct DDL for RAW type" do
      result =
        create_ddl("raw_ddl_test", [
          {:add, :id, :bigserial, [primary_key: true]},
          {:add, :raw_field, :raw, [size: 50]},
          {:add, :long_raw_field, :long_raw, []}
        ])

      assert result =~ "CREATE TABLE"
      assert result =~ ~s("RAW_DDL_TEST")
      assert result =~ "RAW(50)"
      assert result =~ "LONG RAW"
    end
  end

  describe "ROWID in Ecto DDL" do
    test "generates correct DDL for ROWID types" do
      result =
        create_ddl("rowid_ddl_test", [
          {:add, :id, :bigserial, [primary_key: true]},
          {:add, :row_ref, :rowid, []},
          {:add, :universal_row_ref, :urowid, []}
        ])

      assert result =~ "CREATE TABLE"
      assert result =~ ~s("ROWID_DDL_TEST")
      assert result =~ "ROWID"
      assert result =~ "UROWID"
    end
  end
end
