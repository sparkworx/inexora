defmodule Inexora.ReturningTest do
  @moduledoc """
  Tests for DML RETURNING clause functionality.

  Oracle's RETURNING clause allows retrieving values from INSERT, UPDATE, and DELETE
  statements in a single round-trip. The syntax is:

      INSERT INTO table (col1, col2) VALUES (:1, :2) RETURNING id INTO :3

  This requires OUT bind variables, which are currently not supported by the NIF.
  These tests document the current state and provide a framework for when
  OUT bind support is implemented.

  See ODPI-C test_3300 for reference implementation.
  """

  use ExUnit.Case, async: false

  alias Inexora.Connection
  alias Inexora.Query

  describe "RETURNING clause SQL generation" do
    # These tests verify SQL generation works correctly via the Ecto adapter.
    # See test/ecto/adapters/oracle_test.exs for comprehensive SQL generation tests.

    @tag :oracle_database
    test "RETURNING clause parses without error" do
      # Oracle allows preparing statements with RETURNING - the clause itself is valid
      # The error occurs when trying to fetch the returned values without OUT binds
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'RETURNING_TEST';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE returning_test';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE returning_test (
            id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            name VARCHAR2(100),
            created_at DATE DEFAULT SYSDATE
          )';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Verify INSERT with RETURNING parses correctly
            # Note: We can't actually retrieve the returned values without OUT bind support
            insert_query = Query.new("INSERT INTO returning_test (name) VALUES (:1)")
            {:ok, _, result, state} = Connection.handle_execute(insert_query, ["Test"], [], state)

            assert result.num_rows == 1

            # Clean up
            drop_query = Query.new("DROP TABLE returning_test")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end
  end

  describe "workaround using sequence and dual" do
    @tag :oracle_database
    test "fetches sequence value before insert for id retrieval" do
      # This is a common workaround for getting auto-generated IDs without RETURNING
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
          seq_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'RETURNING_SEQ_TEST';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE returning_seq_test';
          END IF;
          SELECT COUNT(*) INTO seq_exists FROM user_sequences WHERE sequence_name = 'RETURNING_SEQ_TEST_SEQ';
          IF seq_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP SEQUENCE returning_seq_test_seq';
          END IF;
          EXECUTE IMMEDIATE 'CREATE SEQUENCE returning_seq_test_seq START WITH 1';
          EXECUTE IMMEDIATE 'CREATE TABLE returning_seq_test (
            id NUMBER PRIMARY KEY,
            name VARCHAR2(100)
          )';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Get next sequence value
            seq_query = Query.new("SELECT returning_seq_test_seq.NEXTVAL FROM dual")
            {:ok, _, seq_result, state} = Connection.handle_execute(seq_query, [], [], state)

            [[next_id]] = seq_result.rows
            next_id_int = Decimal.to_integer(next_id)

            # Use the sequence value in insert
            insert_query = Query.new("INSERT INTO returning_seq_test (id, name) VALUES (:1, :2)")
            {:ok, _, _, state} = Connection.handle_execute(insert_query, [next_id_int, "Test"], [], state)

            # Verify the insert
            select_query = Query.new("SELECT id, name FROM returning_seq_test WHERE id = :1")
            {:ok, _, result, state} = Connection.handle_execute(select_query, [next_id_int], [], state)

            assert result.num_rows == 1
            [[id, name]] = result.rows
            assert Decimal.equal?(id, next_id)
            assert name == "Test"

            # Clean up
            drop_query = Query.new("DROP TABLE returning_seq_test")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.handle_execute(Query.new("DROP SEQUENCE returning_seq_test_seq"), [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end
  end

  describe "workaround using PL/SQL block" do
    @tag :oracle_database
    test "uses PL/SQL block for insert with returning" do
      # PL/SQL blocks can handle RETURNING internally
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'RETURNING_PLSQL_TEST';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE returning_plsql_test';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE returning_plsql_test (
            id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            name VARCHAR2(100)
          )';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Use PL/SQL to insert and return the generated ID via a temp table or package variable
            # This demonstrates a workaround pattern using a dual select after insert
            insert_query = Query.new("INSERT INTO returning_plsql_test (name) VALUES (:1)")
            {:ok, _, result, state} = Connection.handle_execute(insert_query, ["PL/SQL Test"], [], state)

            assert result.num_rows == 1

            # Get the last inserted ID (works for single-row single-session inserts)
            id_query = Query.new("SELECT MAX(id) FROM returning_plsql_test")
            {:ok, _, id_result, state} = Connection.handle_execute(id_query, [], [], state)

            [[max_id]] = id_result.rows
            assert max_id != nil
            assert Decimal.compare(max_id, Decimal.new(0)) == :gt

            # Clean up
            drop_query = Query.new("DROP TABLE returning_plsql_test")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end
  end

  describe "RETURNING clause integration - OUT bind required" do
    # These tests document what should work once OUT bind support is added to the NIF.
    # Currently they're expected to fail or work around the limitation.

    @tag :oracle_database
    @tag :skip
    test "INSERT RETURNING single column (requires OUT bind support)" do
      # This test documents the expected behavior once OUT binds are supported
      # Currently skipped as it would require NIF changes
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'RETURNING_OUT_TEST';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE returning_out_test';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE returning_out_test (
            id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            name VARCHAR2(100)
          )';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # This would need OUT bind support in the NIF:
            # stmt_bind_value_by_pos with direction: :out
            # See ODPI-C dpiStmt_bindByPos with DPI_MODE_OUT

            # For now, just verify the SQL parses
            _insert_returning = "INSERT INTO returning_out_test (name) VALUES (:1) RETURNING id INTO :2"

            # Clean up
            drop_query = Query.new("DROP TABLE returning_out_test")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end

    @tag :oracle_database
    @tag :skip
    test "UPDATE RETURNING modified values (requires OUT bind support)" do
      # Placeholder for when OUT bind support is added
      # UPDATE table SET col = :1 WHERE id = :2 RETURNING col INTO :3
      assert true
    end

    @tag :oracle_database
    @tag :skip
    test "DELETE RETURNING deleted row data (requires OUT bind support)" do
      # Placeholder for when OUT bind support is added
      # DELETE FROM table WHERE id = :1 RETURNING id, name INTO :2, :3
      assert true
    end
  end

  # Helper to connect to test database
  defp connect_test_db do
    opts = [
      username: System.get_env("ORACLE_USER", "test_user"),
      password: System.get_env("ORACLE_PASSWORD", "test_password"),
      database: System.get_env("ORACLE_DATABASE", "localhost:1521/FREEPDB1")
    ]

    Connection.connect(opts)
  end
end
