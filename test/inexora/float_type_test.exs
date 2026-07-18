defmodule Inexora.FloatTypeTest do
  use ExUnit.Case, async: false

  import Inexora.TestHelpers

  @moduletag :oracle_database

  alias Inexora.{Connection, Query, Result}

  setup_all do
    {:ok, conn} = DBConnection.start_link(Connection, test_connection_opts())

    # Create test table with BINARY_FLOAT and BINARY_DOUBLE columns
    DBConnection.execute(conn, %Query{sql: """
      DECLARE
        table_exists NUMBER;
      BEGIN
        SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'FLOAT_TYPE_TEST';
        IF table_exists > 0 THEN
          EXECUTE IMMEDIATE 'DROP TABLE float_type_test';
        END IF;
        EXECUTE IMMEDIATE 'CREATE TABLE float_type_test (
          id NUMBER(19) PRIMARY KEY,
          float_val BINARY_FLOAT,
          double_val BINARY_DOUBLE
        )';
      END;
    """}, [])

    on_exit(fn ->
      try do
        DBConnection.execute(conn, %Query{sql: "DROP TABLE float_type_test"}, [])
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

  describe "BINARY_FLOAT type" do
    test "inserts and retrieves BINARY_FLOAT data", %{conn: conn} do
      float_val = 3.14159

      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO float_type_test (id, float_val) VALUES (:1, :2)"},
          [1, float_val]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT float_val FROM float_type_test WHERE id = :1"},
          [1]
        )

      assert result.num_rows == 1
      assert [[retrieved_val]] = result.rows
      # BINARY_FLOAT has ~7 digits of precision
      assert_in_delta retrieved_val, float_val, 0.0001
    end

    test "handles NULL BINARY_FLOAT", %{conn: conn} do
      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO float_type_test (id, float_val) VALUES (:1, :2)"},
          [2, nil]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT float_val FROM float_type_test WHERE id = :1"},
          [2]
        )

      assert result.num_rows == 1
      assert [[nil]] = result.rows
    end

    test "handles special float values", %{conn: conn} do
      # Test very small and very large values
      small_val = 1.0e-30
      large_val = 1.0e30

      {:ok, _, _} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO float_type_test (id, float_val) VALUES (:1, :2)"},
          [3, small_val]
        )

      {:ok, _, _} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO float_type_test (id, float_val) VALUES (:1, :2)"},
          [4, large_val]
        )

      {:ok, _, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT id, float_val FROM float_type_test WHERE id IN (3, 4) ORDER BY id"},
          []
        )

      assert result.num_rows == 2
      # id comes back as Decimal from NUMBER column
      [[id1, small_retrieved], [id2, large_retrieved]] = result.rows
      assert Decimal.equal?(id1, 3)
      assert Decimal.equal?(id2, 4)

      # Check order of magnitude is preserved
      assert small_retrieved < 1.0e-20
      assert large_retrieved > 1.0e20
    end
  end

  describe "BINARY_DOUBLE type" do
    test "inserts and retrieves BINARY_DOUBLE data", %{conn: conn} do
      double_val = 3.141592653589793

      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO float_type_test (id, double_val) VALUES (:1, :2)"},
          [10, double_val]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT double_val FROM float_type_test WHERE id = :1"},
          [10]
        )

      assert result.num_rows == 1
      assert [[retrieved_val]] = result.rows
      # BINARY_DOUBLE has ~15 digits of precision
      assert_in_delta retrieved_val, double_val, 1.0e-14
    end

    test "handles NULL BINARY_DOUBLE", %{conn: conn} do
      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO float_type_test (id, double_val) VALUES (:1, :2)"},
          [11, nil]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT double_val FROM float_type_test WHERE id = :1"},
          [11]
        )

      assert result.num_rows == 1
      assert [[nil]] = result.rows
    end

    test "handles high precision values", %{conn: conn} do
      # Test a value that requires double precision
      precise_val = 1.23456789012345

      {:ok, _, _} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO float_type_test (id, double_val) VALUES (:1, :2)"},
          [12, precise_val]
        )

      {:ok, _, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT double_val FROM float_type_test WHERE id = :1"},
          [12]
        )

      assert [[retrieved_val]] = result.rows
      assert_in_delta retrieved_val, precise_val, 1.0e-14
    end

    test "handles negative values", %{conn: conn} do
      neg_val = -999.999

      {:ok, _, _} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO float_type_test (id, double_val) VALUES (:1, :2)"},
          [13, neg_val]
        )

      {:ok, _, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT double_val FROM float_type_test WHERE id = :1"},
          [13]
        )

      assert [[retrieved_val]] = result.rows
      assert_in_delta retrieved_val, neg_val, 0.001
    end
  end
end
