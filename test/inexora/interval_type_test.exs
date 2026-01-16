defmodule Inexora.IntervalTypeTest do
  use ExUnit.Case, async: false

  @moduletag :oracle_database

  alias Inexora.{Connection, Query, Result}

  setup_all do
    opts = [
      username: System.get_env("ORACLE_USER", "inexora"),
      password: System.get_env("ORACLE_PASSWORD", "Welcome4321"),
      database: System.get_env("ORACLE_DATABASE", "localhost:1521/FREEPDB1")
    ]

    {:ok, conn} = DBConnection.start_link(Connection, opts)

    # Create test table with INTERVAL columns
    DBConnection.execute(conn, %Query{sql: """
      DECLARE
        table_exists NUMBER;
      BEGIN
        SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'INTERVAL_TYPE_TEST';
        IF table_exists > 0 THEN
          EXECUTE IMMEDIATE 'DROP TABLE interval_type_test';
        END IF;
        EXECUTE IMMEDIATE 'CREATE TABLE interval_type_test (
          id NUMBER(19) PRIMARY KEY,
          ds_val INTERVAL DAY TO SECOND,
          ym_val INTERVAL YEAR TO MONTH
        )';
      END;
    """}, [])

    on_exit(fn ->
      try do
        DBConnection.execute(conn, %Query{sql: "DROP TABLE interval_type_test"}, [])
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

  describe "INTERVAL DAY TO SECOND type" do
    test "retrieves INTERVAL DAY TO SECOND data", %{conn: conn} do
      # Insert using SQL literal
      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO interval_type_test (id, ds_val) VALUES (:1, INTERVAL '5 04:30:15.123456' DAY TO SECOND)"},
          [1]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ds_val FROM interval_type_test WHERE id = :1"},
          [1]
        )

      assert result.num_rows == 1
      assert [[{:interval_ds, days, hours, minutes, seconds, fseconds}]] = result.rows
      assert days == 5
      assert hours == 4
      assert minutes == 30
      assert seconds == 15
      # fseconds is in nanoseconds
      assert fseconds == 123_456_000
    end

    test "inserts and retrieves INTERVAL DAY TO SECOND data with binding", %{conn: conn} do
      # Insert with bound parameter: 2 days, 3 hours, 15 minutes, 30 seconds, 500000000 nanoseconds
      interval = {:interval_ds, 2, 3, 15, 30, 500_000_000}

      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO interval_type_test (id, ds_val) VALUES (:1, :2)"},
          [2, interval]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ds_val FROM interval_type_test WHERE id = :1"},
          [2]
        )

      assert result.num_rows == 1
      assert [[{:interval_ds, 2, 3, 15, 30, 500_000_000}]] = result.rows
    end

    test "handles NULL INTERVAL DAY TO SECOND", %{conn: conn} do
      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO interval_type_test (id, ds_val) VALUES (:1, NULL)"},
          [3]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ds_val FROM interval_type_test WHERE id = :1"},
          [3]
        )

      assert result.num_rows == 1
      assert [[nil]] = result.rows
    end

    test "handles zero interval", %{conn: conn} do
      interval = {:interval_ds, 0, 0, 0, 0, 0}

      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO interval_type_test (id, ds_val) VALUES (:1, :2)"},
          [4, interval]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ds_val FROM interval_type_test WHERE id = :1"},
          [4]
        )

      assert result.num_rows == 1
      assert [[{:interval_ds, 0, 0, 0, 0, 0}]] = result.rows
    end
  end

  describe "INTERVAL YEAR TO MONTH type" do
    test "retrieves INTERVAL YEAR TO MONTH data", %{conn: conn} do
      # Insert using SQL literal
      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO interval_type_test (id, ym_val) VALUES (:1, INTERVAL '3-6' YEAR TO MONTH)"},
          [10]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ym_val FROM interval_type_test WHERE id = :1"},
          [10]
        )

      assert result.num_rows == 1
      assert [[{:interval_ym, years, months}]] = result.rows
      assert years == 3
      assert months == 6
    end

    test "inserts and retrieves INTERVAL YEAR TO MONTH data with binding", %{conn: conn} do
      # Insert with bound parameter: 5 years, 11 months
      interval = {:interval_ym, 5, 11}

      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO interval_type_test (id, ym_val) VALUES (:1, :2)"},
          [11, interval]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ym_val FROM interval_type_test WHERE id = :1"},
          [11]
        )

      assert result.num_rows == 1
      assert [[{:interval_ym, 5, 11}]] = result.rows
    end

    test "handles NULL INTERVAL YEAR TO MONTH", %{conn: conn} do
      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO interval_type_test (id, ym_val) VALUES (:1, NULL)"},
          [12]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ym_val FROM interval_type_test WHERE id = :1"},
          [12]
        )

      assert result.num_rows == 1
      assert [[nil]] = result.rows
    end

    test "handles zero interval", %{conn: conn} do
      interval = {:interval_ym, 0, 0}

      {:ok, _query, %Result{num_rows: 1}} =
        DBConnection.execute(
          conn,
          %Query{sql: "INSERT INTO interval_type_test (id, ym_val) VALUES (:1, :2)"},
          [13, interval]
        )

      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ym_val FROM interval_type_test WHERE id = :1"},
          [13]
        )

      assert result.num_rows == 1
      assert [[{:interval_ym, 0, 0}]] = result.rows
    end
  end

  describe "INTERVAL types in Ecto DDL" do
    test "generates correct DDL for interval types" do
      alias Ecto.Adapters.Oracle.Connection, as: SQL

      columns = [
        {:add, :id, :bigserial, [primary_key: true]},
        {:add, :duration, :interval_day_to_second, []},
        {:add, :period, :interval_year_to_month, []}
      ]

      table = %Ecto.Migration.Table{name: "interval_ddl_test"}
      [ddl] = SQL.execute_ddl({:create, table, columns})
      result = IO.iodata_to_binary(ddl)

      assert result =~ "CREATE TABLE"
      assert result =~ ~s("INTERVAL_DDL_TEST")
      assert result =~ "INTERVAL DAY TO SECOND"
      assert result =~ "INTERVAL YEAR TO MONTH"
    end
  end
end
