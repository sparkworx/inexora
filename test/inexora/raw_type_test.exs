defmodule Inexora.RawTypeTest do
  use ExUnit.Case, async: false

  import Inexora.TestHelpers

  @moduletag :oracle_database

  alias Inexora.{Connection, Query, Result}

  setup_all do
    {:ok, conn} = DBConnection.start_link(Connection, test_connection_opts())

    # Create test table with RAW columns
    DBConnection.execute(conn, %Query{sql: """
      DECLARE
        table_exists NUMBER;
      BEGIN
        SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'RAW_TYPE_TEST';
        IF table_exists > 0 THEN
          EXECUTE IMMEDIATE 'DROP TABLE raw_type_test';
        END IF;
        EXECUTE IMMEDIATE 'CREATE TABLE raw_type_test (
          id NUMBER(19) PRIMARY KEY,
          raw_data RAW(100),
          long_raw_data LONG RAW
        )';
      END;
    """}, [])

    on_exit(fn ->
      try do
        DBConnection.execute(conn, %Query{sql: "DROP TABLE raw_type_test"}, [])
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end

      if Process.alive?(conn) do
        GenServer.stop(conn)
      end
    end)

    {:ok, conn: conn}
  end

  describe "RAW type" do
    test "inserts and retrieves RAW data", %{conn: conn} do
      # Insert binary data using {:raw, binary} wrapper
      raw_data = <<0x01, 0x02, 0x03, 0x04, 0x05>>

      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO raw_type_test (id, raw_data) VALUES (:1, :2)"},
          [1, {:raw, raw_data}]
        )

      # Retrieve it
      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT raw_data FROM raw_type_test WHERE id = :1"},
          [1]
        )

      assert result.num_rows == 1
      assert [[retrieved_data]] = result.rows
      assert retrieved_data == raw_data
    end

    test "handles NULL RAW data", %{conn: conn} do
      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO raw_type_test (id, raw_data) VALUES (:1, :2)"},
          [2, {:raw, nil}]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT raw_data FROM raw_type_test WHERE id = :1"},
          [2]
        )

      assert result.num_rows == 1
      assert [[nil]] = result.rows
    end

    test "handles larger RAW data up to column size", %{conn: conn} do
      # Create 100 bytes of data (max size of our RAW column)
      raw_data = :crypto.strong_rand_bytes(100)

      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO raw_type_test (id, raw_data) VALUES (:1, :2)"},
          [3, {:raw, raw_data}]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT raw_data FROM raw_type_test WHERE id = :1"},
          [3]
        )

      assert result.num_rows == 1
      assert [[retrieved_data]] = result.rows
      assert retrieved_data == raw_data
    end
  end

  describe "LONG RAW type" do
    test "inserts and retrieves LONG RAW data", %{conn: conn} do
      # Insert larger binary data using {:raw, binary} wrapper
      long_raw_data = :crypto.strong_rand_bytes(1000)

      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO raw_type_test (id, long_raw_data) VALUES (:1, :2)"},
          [10, {:raw, long_raw_data}]
        )

      # Retrieve it
      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT long_raw_data FROM raw_type_test WHERE id = :1"},
          [10]
        )

      assert result.num_rows == 1
      assert [[retrieved_data]] = result.rows
      assert retrieved_data == long_raw_data
    end

    test "handles NULL LONG RAW data", %{conn: conn} do
      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO raw_type_test (id, long_raw_data) VALUES (:1, :2)"},
          [11, {:raw, nil}]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT long_raw_data FROM raw_type_test WHERE id = :1"},
          [11]
        )

      assert result.num_rows == 1
      assert [[nil]] = result.rows
    end
  end

  describe "RAW in Ecto DDL" do
    test "generates correct DDL for RAW type" do
      alias Ecto.Adapters.Oracle.Connection, as: SQL

      columns = [
        {:add, :id, :bigserial, [primary_key: true]},
        {:add, :raw_field, :raw, [size: 50]},
        {:add, :long_raw_field, :long_raw, []}
      ]

      table = %Ecto.Migration.Table{name: "raw_ddl_test"}
      [ddl] = SQL.execute_ddl({:create, table, columns})
      result = IO.iodata_to_binary(ddl)

      assert result =~ "CREATE TABLE"
      assert result =~ ~s("RAW_DDL_TEST")
      assert result =~ "RAW(50)"
      assert result =~ "LONG RAW"
    end
  end
end
