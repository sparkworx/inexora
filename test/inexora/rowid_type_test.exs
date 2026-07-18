defmodule Inexora.RowidTypeTest do
  use ExUnit.Case, async: false

  import Inexora.TestHelpers

  @moduletag :oracle_database

  alias Inexora.{Connection, Query}

  setup_all do
    {:ok, conn} = DBConnection.start_link(Connection, test_connection_opts())

    # Create test table for ROWID tests
    DBConnection.execute(conn, %Query{sql: """
      DECLARE
        table_exists NUMBER;
      BEGIN
        SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'ROWID_TYPE_TEST';
        IF table_exists > 0 THEN
          EXECUTE IMMEDIATE 'DROP TABLE rowid_type_test';
        END IF;
        EXECUTE IMMEDIATE 'CREATE TABLE rowid_type_test (
          id NUMBER(19) PRIMARY KEY,
          name VARCHAR2(100)
        )';
      END;
    """}, [])

    # Insert test data
    DBConnection.execute(
      conn,
      %Query{sql: "INSERT INTO rowid_type_test (id, name) VALUES (:1, :2)"},
      [1, "Alice"]
    )

    DBConnection.execute(
      conn,
      %Query{sql: "INSERT INTO rowid_type_test (id, name) VALUES (:1, :2)"},
      [2, "Bob"]
    )

    on_exit(fn ->
      try do
        DBConnection.execute(conn, %Query{sql: "DROP TABLE rowid_type_test"}, [])
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

  describe "ROWID type" do
    test "retrieves ROWID pseudo-column", %{conn: conn} do
      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ROWID, id, name FROM rowid_type_test WHERE id = :1"},
          [1]
        )

      assert result.num_rows == 1
      assert [[rowid, id, name]] = result.rows

      # ROWID should be a string of 18 characters (base64 encoded)
      assert is_binary(rowid)
      assert byte_size(rowid) == 18
      assert Decimal.equal?(id, 1)
      assert name == "Alice"
    end

    test "retrieves multiple ROWIDs", %{conn: conn} do
      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ROWID, name FROM rowid_type_test ORDER BY id"},
          []
        )

      assert result.num_rows == 2
      [[rowid1, name1], [rowid2, name2]] = result.rows

      # Each ROWID should be unique
      assert is_binary(rowid1)
      assert is_binary(rowid2)
      assert rowid1 != rowid2
      assert name1 == "Alice"
      assert name2 == "Bob"
    end

    test "ROWID has expected format", %{conn: conn} do
      {:ok, _query, result} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ROWID FROM rowid_type_test WHERE id = :1"},
          [1]
        )

      assert [[rowid]] = result.rows

      # ROWID format: OOOOOOFFFBBBBBBRRR
      # O = data object number, F = relative file number
      # B = block number, R = row number
      # Total 18 chars in base64 encoding
      assert byte_size(rowid) == 18
      assert String.printable?(rowid)
    end

    test "can use ROWID with CHARTOROWID for binding", %{conn: conn} do
      # First, get the ROWID as a string for a row
      {:ok, _query, result1} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT ROWID FROM rowid_type_test WHERE id = :1"},
          [1]
        )

      assert [[rowid_str]] = result1.rows

      # Use CHARTOROWID to convert the string back to ROWID for comparison
      {:ok, _query, result2} =
        DBConnection.execute(
          conn,
          %Query{sql: "SELECT id, name FROM rowid_type_test WHERE ROWID = CHARTOROWID(:1)"},
          [rowid_str]
        )

      assert result2.num_rows == 1
      assert [[id, name]] = result2.rows
      assert Decimal.equal?(id, 1)
      assert name == "Alice"
    end
  end
end
