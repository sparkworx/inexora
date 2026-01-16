defmodule Inexora.CursorTest do
  use ExUnit.Case, async: false

  alias Inexora.Connection
  alias Inexora.Cursor
  alias Inexora.Nif
  alias Inexora.Query

  @moduletag :oracle_database

  defp connect_test_db do
    opts = [
      username: System.get_env("ORACLE_USER", "inexora"),
      password: System.get_env("ORACLE_PASSWORD", "Welcome4321"),
      database: System.get_env("ORACLE_DATABASE", "localhost:1521/FREEPDB1")
    ]

    Connection.connect(opts)
  end

  describe "cursor open/fetch/close" do
    test "opens cursor for SELECT query" do
      {:ok, state} = connect_test_db()

      try do
        query = Query.new("SELECT 1 AS num, 'hello' AS str FROM dual")
        {:ok, cursor} = Cursor.open(state.conn, query, [])

        assert cursor.num_columns == 2
        assert cursor.done == false
        assert is_reference(cursor.stmt)

        Cursor.close(cursor)
      after
        Connection.disconnect(nil, state)
      end
    end

    test "fetches rows from cursor" do
      {:ok, state} = connect_test_db()

      try do
        query = Query.new("SELECT LEVEL AS num FROM dual CONNECT BY LEVEL <= 5")
        {:ok, cursor} = Cursor.open(state.conn, query, [], max_rows: 2)

        # First fetch - should get 2 rows
        {:ok, rows1, cursor1} = Cursor.fetch(cursor)
        assert length(rows1) == 2
        assert cursor1.done == false

        # Second fetch - should get 2 more rows
        {:ok, rows2, cursor2} = Cursor.fetch(cursor1)
        assert length(rows2) == 2
        assert cursor2.done == false

        # Third fetch - should get last row
        {:ok, rows3, cursor3} = Cursor.fetch(cursor2)
        assert length(rows3) == 1
        assert cursor3.done == true

        # Fourth fetch - cursor is done
        {:done, _cursor4} = Cursor.fetch(cursor3)

        Cursor.close(cursor3)
      after
        Connection.disconnect(nil, state)
      end
    end

    test "closes cursor correctly" do
      {:ok, state} = connect_test_db()

      try do
        query = Query.new("SELECT 1 FROM dual")
        {:ok, cursor} = Cursor.open(state.conn, query, [])

        assert :ok = Cursor.close(cursor)
        # Closing again should be safe
        assert :ok = Cursor.close(cursor)
      after
        Connection.disconnect(nil, state)
      end
    end

    test "opens cursor with SQL string directly" do
      {:ok, state} = connect_test_db()

      try do
        {:ok, cursor} = Cursor.open(state.conn, "SELECT 1 FROM dual", [])

        assert cursor.num_columns == 1
        assert cursor.done == false

        Cursor.close(cursor)
      after
        Connection.disconnect(nil, state)
      end
    end

    test "returns error for non-query statement" do
      {:ok, state} = connect_test_db()

      try do
        # DML statement - not a query
        result = Cursor.open(state.conn, "BEGIN NULL; END;", [])

        assert {:error, _} = result
      after
        Connection.disconnect(nil, state)
      end
    end
  end

  describe "cursor stream" do
    test "streams all rows" do
      {:ok, state} = connect_test_db()

      try do
        query = Query.new("SELECT LEVEL AS num FROM dual CONNECT BY LEVEL <= 10")

        # Stream emits each row as [col1, col2, ...]
        rows =
          Cursor.stream(state.conn, query, [], max_rows: 3)
          |> Enum.to_list()

        assert length(rows) == 10

        # Verify row values (numbers come back as Decimals)
        nums = Enum.map(rows, fn [num] -> Decimal.to_integer(num) end)
        assert nums == Enum.to_list(1..10)
      after
        Connection.disconnect(nil, state)
      end
    end

    test "stream with take stops early" do
      {:ok, state} = connect_test_db()

      try do
        query = Query.new("SELECT LEVEL AS num FROM dual CONNECT BY LEVEL <= 1000")

        # Take only 5 rows even though query could return 1000
        rows =
          Cursor.stream(state.conn, query, [], max_rows: 100)
          |> Enum.take(5)

        assert length(rows) == 5
      after
        Connection.disconnect(nil, state)
      end
    end

    test "stream with params" do
      {:ok, state} = connect_test_db()

      try do
        query = Query.new("SELECT LEVEL AS num FROM dual WHERE :1 = 1 CONNECT BY LEVEL <= :2")

        # Stream emits each row as [col1, ...]
        rows =
          Cursor.stream(state.conn, query, [1, 5], max_rows: 2)
          |> Enum.to_list()

        assert length(rows) == 5
      after
        Connection.disconnect(nil, state)
      end
    end

    test "stream with multiple columns" do
      {:ok, state} = connect_test_db()

      try do
        query = Query.new("SELECT LEVEL AS num, 'row_' || LEVEL AS name FROM dual CONNECT BY LEVEL <= 3")

        # Stream emits each row as [col1, col2, ...]
        rows =
          Cursor.stream(state.conn, query, [], max_rows: 10)
          |> Enum.to_list()

        assert length(rows) == 3

        # Numbers are Decimals
        assert [num1, name1] = Enum.at(rows, 0)
        assert Decimal.to_integer(num1) == 1
        assert name1 == "row_1"

        assert [num2, name2] = Enum.at(rows, 1)
        assert Decimal.to_integer(num2) == 2
        assert name2 == "row_2"

        assert [num3, name3] = Enum.at(rows, 2)
        assert Decimal.to_integer(num3) == 3
        assert name3 == "row_3"
      after
        Connection.disconnect(nil, state)
      end
    end
  end

  describe "NIF cursor functions" do
    test "stmt_set_fetch_array_size and stmt_get_fetch_array_size" do
      {:ok, state} = connect_test_db()

      try do
        {:ok, stmt} = Nif.stmt_prepare(state.conn, "SELECT 1 FROM dual")

        assert :ok = Nif.stmt_set_fetch_array_size(stmt, 50)
        assert {:ok, 50} = Nif.stmt_get_fetch_array_size(stmt)

        assert :ok = Nif.stmt_set_fetch_array_size(stmt, 200)
        assert {:ok, 200} = Nif.stmt_get_fetch_array_size(stmt)

        Nif.stmt_close(stmt)
      after
        Connection.disconnect(nil, state)
      end
    end

    test "stmt_set_prefetch_rows and stmt_get_prefetch_rows" do
      {:ok, state} = connect_test_db()

      try do
        {:ok, stmt} = Nif.stmt_prepare(state.conn, "SELECT 1 FROM dual")

        assert :ok = Nif.stmt_set_prefetch_rows(stmt, 10)
        assert {:ok, 10} = Nif.stmt_get_prefetch_rows(stmt)

        assert :ok = Nif.stmt_set_prefetch_rows(stmt, 100)
        assert {:ok, 100} = Nif.stmt_get_prefetch_rows(stmt)

        Nif.stmt_close(stmt)
      after
        Connection.disconnect(nil, state)
      end
    end

    test "stmt_fetch_rows returns correct fetch info" do
      {:ok, state} = connect_test_db()

      try do
        {:ok, stmt} = Nif.stmt_prepare(state.conn, "SELECT LEVEL FROM dual CONNECT BY LEVEL <= 5")
        {:ok, _num_cols} = Nif.stmt_execute(stmt)

        # Fetch all 5 rows at once
        {:ok, {rows_fetched, _buffer_idx, more}} = Nif.stmt_fetch_rows(stmt, 10)
        assert rows_fetched == 5
        assert more == false

        Nif.stmt_close(stmt)
      after
        Connection.disconnect(nil, state)
      end
    end

    test "stmt_fetch_rows with small batch size" do
      {:ok, state} = connect_test_db()

      try do
        {:ok, stmt} = Nif.stmt_prepare(state.conn, "SELECT LEVEL FROM dual CONNECT BY LEVEL <= 3")
        {:ok, _num_cols} = Nif.stmt_execute(stmt)

        # Fetch 2 rows - should indicate more available
        {:ok, {rows_fetched, _buffer_idx, more}} = Nif.stmt_fetch_rows(stmt, 2)
        assert rows_fetched == 2
        assert more == true

        Nif.stmt_close(stmt)
      after
        Connection.disconnect(nil, state)
      end
    end
  end
end
