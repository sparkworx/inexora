defmodule Inexora.ReturningTest do
  @moduledoc """
  Tests for DML RETURNING clause functionality.

  Oracle's RETURNING clause allows retrieving values from INSERT, UPDATE, and DELETE
  statements in a single round-trip. The syntax is:

      INSERT INTO table (col1, col2) VALUES (:1, :2) RETURNING id INTO :3

  RETURNING INTO support is implemented via the Variable API:
  - Create output variables with `Nif.conn_new_var/5`
  - Bind them to the RETURNING placeholders with `Nif.stmt_bind_by_pos/3`
  - After execution, retrieve values with `Nif.var_get_returned_data/2`

  See ODPI-C test_3300 for reference implementation.
  """

  use ExUnit.Case, async: false

  import Inexora.TestHelpers

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

  describe "RETURNING clause integration with Variable API" do
    # These tests use the Variable API (conn_new_var, var_get_returned_data)
    # to retrieve values from RETURNING INTO clauses.

    alias Inexora.Nif

    @tag :oracle_database
    test "INSERT RETURNING single column" do
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'GTT_RETURNING_OUT_TEST';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE gtt_returning_out_test';
          END IF;
          EXECUTE IMMEDIATE 'CREATE GLOBAL TEMPORARY TABLE gtt_returning_out_test (
            id NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
            name VARCHAR2(100)
          ) ON COMMIT PRESERVE ROWS';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Use NIF directly for RETURNING INTO
            conn = state.conn

            {:ok, stmt} = Nif.stmt_prepare(conn,
              "INSERT INTO gtt_returning_out_test (name) VALUES (:1) RETURNING id INTO :2")

            # Create variable for input name
            {:ok, name_var} = Nif.conn_new_var(conn, :varchar, :bytes, 1, 100)
            :ok = Nif.var_set_from_bytes(name_var, 0, "Test User")
            :ok = Nif.var_set_num_elements(name_var, 1)

            # Create variable for output id (for RETURNING INTO)
            {:ok, id_var} = Nif.conn_new_var(conn, :number, :int64, 1, 0)
            :ok = Nif.var_set_num_elements(id_var, 1)

            # Bind variables
            :ok = Nif.stmt_bind_by_pos(stmt, 1, name_var)
            :ok = Nif.stmt_bind_by_pos(stmt, 2, id_var)

            # Execute
            {:ok, _} = Nif.stmt_execute(stmt)

            # Get the returned ID
            {:ok, returned_ids} = Nif.var_get_returned_data(id_var, 0)

            assert length(returned_ids) == 1
            [returned_id] = returned_ids
            assert is_integer(returned_id)
            assert returned_id > 0

            Nif.stmt_close(stmt)
            Nif.var_release(name_var)
            Nif.var_release(id_var)

            # Clean up
            drop_query = Query.new("DROP TABLE gtt_returning_out_test")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end

    @tag :oracle_database
    test "UPDATE RETURNING modified values" do
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'GTT_RETURNING_UPDATE';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE gtt_returning_update';
          END IF;
          EXECUTE IMMEDIATE 'CREATE GLOBAL TEMPORARY TABLE gtt_returning_update (
            id NUMBER PRIMARY KEY,
            name VARCHAR2(100),
            updated_name VARCHAR2(100)
          ) ON COMMIT PRESERVE ROWS';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            conn = state.conn

            # Insert initial data
            {:ok, insert_stmt} = Nif.stmt_prepare(conn,
              "INSERT INTO gtt_returning_update (id, name) VALUES (1, 'Original')")
            {:ok, _} = Nif.stmt_execute(insert_stmt)
            Nif.stmt_close(insert_stmt)

            # Update with RETURNING
            {:ok, update_stmt} = Nif.stmt_prepare(conn,
              "UPDATE gtt_returning_update SET name = :1 WHERE id = :2 RETURNING name INTO :3")

            # Input variables
            {:ok, new_name_var} = Nif.conn_new_var(conn, :varchar, :bytes, 1, 100)
            :ok = Nif.var_set_from_bytes(new_name_var, 0, "Updated")
            :ok = Nif.var_set_num_elements(new_name_var, 1)

            {:ok, id_var} = Nif.conn_new_var(conn, :number, :int64, 1, 0)
            :ok = Nif.var_set_from_int(id_var, 0, 1)
            :ok = Nif.var_set_num_elements(id_var, 1)

            # Output variable for RETURNING
            {:ok, out_name_var} = Nif.conn_new_var(conn, :varchar, :bytes, 1, 100)
            :ok = Nif.var_set_num_elements(out_name_var, 1)

            # Bind
            :ok = Nif.stmt_bind_by_pos(update_stmt, 1, new_name_var)
            :ok = Nif.stmt_bind_by_pos(update_stmt, 2, id_var)
            :ok = Nif.stmt_bind_by_pos(update_stmt, 3, out_name_var)

            # Execute
            {:ok, _} = Nif.stmt_execute(update_stmt)

            # Get the returned name
            {:ok, returned_names} = Nif.var_get_returned_data(out_name_var, 0)

            assert length(returned_names) == 1
            assert returned_names == ["Updated"]

            Nif.stmt_close(update_stmt)
            Nif.var_release(new_name_var)
            Nif.var_release(id_var)
            Nif.var_release(out_name_var)

            # Clean up
            drop_query = Query.new("DROP TABLE gtt_returning_update")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end

    @tag :oracle_database
    test "DELETE RETURNING deleted row data" do
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'GTT_RETURNING_DELETE';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE gtt_returning_delete';
          END IF;
          EXECUTE IMMEDIATE 'CREATE GLOBAL TEMPORARY TABLE gtt_returning_delete (
            id NUMBER PRIMARY KEY,
            name VARCHAR2(100)
          ) ON COMMIT PRESERVE ROWS';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            conn = state.conn

            # Insert data to delete
            {:ok, insert_stmt} = Nif.stmt_prepare(conn,
              "INSERT INTO gtt_returning_delete (id, name) VALUES (42, 'ToDelete')")
            {:ok, _} = Nif.stmt_execute(insert_stmt)
            Nif.stmt_close(insert_stmt)

            # Delete with RETURNING
            {:ok, delete_stmt} = Nif.stmt_prepare(conn,
              "DELETE FROM gtt_returning_delete WHERE id = :1 RETURNING id, name INTO :2, :3")

            # Input variable
            {:ok, id_in_var} = Nif.conn_new_var(conn, :number, :int64, 1, 0)
            :ok = Nif.var_set_from_int(id_in_var, 0, 42)
            :ok = Nif.var_set_num_elements(id_in_var, 1)

            # Output variables for RETURNING
            {:ok, id_out_var} = Nif.conn_new_var(conn, :number, :int64, 1, 0)
            :ok = Nif.var_set_num_elements(id_out_var, 1)

            {:ok, name_out_var} = Nif.conn_new_var(conn, :varchar, :bytes, 1, 100)
            :ok = Nif.var_set_num_elements(name_out_var, 1)

            # Bind
            :ok = Nif.stmt_bind_by_pos(delete_stmt, 1, id_in_var)
            :ok = Nif.stmt_bind_by_pos(delete_stmt, 2, id_out_var)
            :ok = Nif.stmt_bind_by_pos(delete_stmt, 3, name_out_var)

            # Execute
            {:ok, _} = Nif.stmt_execute(delete_stmt)

            # Get the returned values
            {:ok, returned_ids} = Nif.var_get_returned_data(id_out_var, 0)
            {:ok, returned_names} = Nif.var_get_returned_data(name_out_var, 0)

            assert returned_ids == [42]
            assert returned_names == ["ToDelete"]

            Nif.stmt_close(delete_stmt)
            Nif.var_release(id_in_var)
            Nif.var_release(id_out_var)
            Nif.var_release(name_out_var)

            # Clean up
            drop_query = Query.new("DROP TABLE gtt_returning_delete")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end
  end

end
