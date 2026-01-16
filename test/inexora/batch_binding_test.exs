defmodule Inexora.BatchBindingTest do
  @moduledoc """
  Tests for batch/array binding functionality.

  These tests verify:
  1. Creating variables with array support
  2. Setting values at array positions
  3. Batch execution with stmt_execute_many
  4. RETURNING INTO clause support via var_get_returned_data
  """

  use ExUnit.Case, async: false

  alias Inexora.Nif

  # Helper to connect to test database
  defp connect_test_db do
    {:ok, ctx} = Nif.context_create()

    username = System.get_env("ORACLE_USER", "test_user")
    password = System.get_env("ORACLE_PASSWORD", "test_password")
    database = System.get_env("ORACLE_DATABASE", "localhost:1521/FREEPDB1")

    case Nif.conn_create(ctx, username, password, database) do
      {:ok, conn} -> {:ok, ctx, conn}
      {:error, _} = error -> error
    end
  end

  defp cleanup(ctx, conn) do
    Nif.conn_close(conn)
    Nif.context_destroy(ctx)
  end

  describe "conn_new_var/5" do
    @tag :oracle_database
    test "creates a varchar variable" do
      with {:ok, ctx, conn} <- connect_test_db() do
        # Create variable for 5 strings, each up to 100 chars
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        assert is_reference(var)

        # Cleanup
        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "creates a number variable with int64 native type" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :number, :int64, 10, 0)

        assert is_reference(var)

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "creates a number variable with bytes native type" do
      with {:ok, ctx, conn} <- connect_test_db() do
        # NUMBER as bytes for decimal precision
        {:ok, var} = Nif.conn_new_var(conn, :number, :bytes, 10, 50)

        assert is_reference(var)

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "returns error for invalid oracle type" do
      with {:ok, ctx, conn} <- connect_test_db() do
        result = Nif.conn_new_var(conn, :invalid_type, :bytes, 10, 100)

        assert {:error, "unsupported_oracle_type"} = result

        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "returns error for invalid native type" do
      with {:ok, ctx, conn} <- connect_test_db() do
        result = Nif.conn_new_var(conn, :varchar, :invalid_native, 10, 100)

        assert {:error, "unsupported_native_type"} = result

        cleanup(ctx, conn)
      end
    end
  end

  describe "var_set_num_elements/2" do
    @tag :oracle_database
    test "sets number of elements in array" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 10, 100)

        assert :ok = Nif.var_set_num_elements(var, 5)

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "returns error when exceeding max array size" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        result = Nif.var_set_num_elements(var, 10)

        assert {:error, "num_elements_exceeds_max_array_size"} = result

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "var_get_num_elements/1" do
    @tag :oracle_database
    test "gets number of elements in array" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 10, 100)

        :ok = Nif.var_set_num_elements(var, 5)
        {:ok, count} = Nif.var_get_num_elements(var)

        assert count == 5

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "var_set_from_bytes/3" do
    @tag :oracle_database
    test "sets bytes values at array positions" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        assert :ok = Nif.var_set_from_bytes(var, 0, "first")
        assert :ok = Nif.var_set_from_bytes(var, 1, "second")
        assert :ok = Nif.var_set_from_bytes(var, 2, "third")

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "returns error for out of bounds position" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        result = Nif.var_set_from_bytes(var, 10, "out of bounds")

        assert {:error, "position_out_of_bounds"} = result

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "var_set_from_int/3" do
    @tag :oracle_database
    test "sets integer values at array positions" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :native_int, :int64, 5, 0)

        assert :ok = Nif.var_set_from_int(var, 0, 100)
        assert :ok = Nif.var_set_from_int(var, 1, 200)
        assert :ok = Nif.var_set_from_int(var, 2, -300)

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "var_set_from_double/3" do
    @tag :oracle_database
    test "sets double values at array positions" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :native_double, :double, 5, 0)

        assert :ok = Nif.var_set_from_double(var, 0, 3.14)
        assert :ok = Nif.var_set_from_double(var, 1, 2.71828)
        # Integer should also work
        assert :ok = Nif.var_set_from_double(var, 2, 42)

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "var_set_null/2" do
    @tag :oracle_database
    test "sets NULL at array position" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        assert :ok = Nif.var_set_from_bytes(var, 0, "not null")
        assert :ok = Nif.var_set_null(var, 1)

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "var_get_value/2" do
    @tag :oracle_database
    test "gets value at array position after setting bytes" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        :ok = Nif.var_set_from_bytes(var, 0, "test_value")
        {:ok, value} = Nif.var_get_value(var, 0)

        assert value == "test_value"

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "gets nil for NULL value" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        :ok = Nif.var_set_null(var, 0)
        {:ok, value} = Nif.var_get_value(var, 0)

        assert value == nil

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "gets integer value at array position" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :native_int, :int64, 5, 0)

        :ok = Nif.var_set_from_int(var, 0, 12345)
        {:ok, value} = Nif.var_get_value(var, 0)

        assert value == 12345

        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "stmt_bind_by_pos/3" do
    @tag :oracle_database
    test "binds variable by position" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, stmt} = Nif.stmt_prepare(conn, "SELECT :1 FROM dual")
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 1, 100)

        :ok = Nif.var_set_from_bytes(var, 0, "test_bind")
        :ok = Nif.var_set_num_elements(var, 1)

        assert :ok = Nif.stmt_bind_by_pos(stmt, 1, var)

        {:ok, _} = Nif.stmt_execute(stmt)
        {:ok, true} = Nif.stmt_fetch(stmt)
        {:ok, value} = Nif.stmt_get_query_value(stmt, 1)

        assert value == "test_bind"

        Nif.stmt_close(stmt)
        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "stmt_bind_by_name/3" do
    @tag :oracle_database
    test "binds variable by name" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, stmt} = Nif.stmt_prepare(conn, "SELECT :VAL FROM dual")
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 1, 100)

        :ok = Nif.var_set_from_bytes(var, 0, "named_bind")
        :ok = Nif.var_set_num_elements(var, 1)

        assert :ok = Nif.stmt_bind_by_name(stmt, "VAL", var)

        {:ok, _} = Nif.stmt_execute(stmt)
        {:ok, true} = Nif.stmt_fetch(stmt)
        {:ok, value} = Nif.stmt_get_query_value(stmt, 1)

        assert value == "named_bind"

        Nif.stmt_close(stmt)
        Nif.var_release(var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "stmt_execute_many/2 batch insert" do
    @tag :oracle_database
    test "inserts multiple rows in one batch" do
      with {:ok, ctx, conn} <- connect_test_db() do
        # Create a temporary table for testing
        {:ok, create_stmt} = Nif.stmt_prepare(conn, """
          DECLARE
            table_exists NUMBER;
          BEGIN
            SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'GTT_BATCH_TEST';
            IF table_exists > 0 THEN
              EXECUTE IMMEDIATE 'DROP TABLE gtt_batch_test';
            END IF;
            EXECUTE IMMEDIATE 'CREATE GLOBAL TEMPORARY TABLE gtt_batch_test (
              id NUMBER,
              name VARCHAR2(100)
            ) ON COMMIT PRESERVE ROWS';
          END;
        """)
        {:ok, _} = Nif.stmt_execute(create_stmt)
        Nif.stmt_close(create_stmt)

        # Prepare batch insert
        {:ok, insert_stmt} = Nif.stmt_prepare(conn, "INSERT INTO gtt_batch_test (id, name) VALUES (:1, :2)")

        # Create variables for batch
        {:ok, id_var} = Nif.conn_new_var(conn, :number, :int64, 5, 0)
        {:ok, name_var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        # Set values for 3 rows
        :ok = Nif.var_set_from_int(id_var, 0, 1)
        :ok = Nif.var_set_from_int(id_var, 1, 2)
        :ok = Nif.var_set_from_int(id_var, 2, 3)

        :ok = Nif.var_set_from_bytes(name_var, 0, "Alice")
        :ok = Nif.var_set_from_bytes(name_var, 1, "Bob")
        :ok = Nif.var_set_from_bytes(name_var, 2, "Charlie")

        :ok = Nif.var_set_num_elements(id_var, 3)
        :ok = Nif.var_set_num_elements(name_var, 3)

        # Bind variables
        :ok = Nif.stmt_bind_by_pos(insert_stmt, 1, id_var)
        :ok = Nif.stmt_bind_by_pos(insert_stmt, 2, name_var)

        # Execute batch
        {:ok, 0} = Nif.stmt_execute_many(insert_stmt, 3)

        Nif.stmt_close(insert_stmt)

        # Verify the data
        {:ok, select_stmt} = Nif.stmt_prepare(conn, "SELECT COUNT(*) FROM gtt_batch_test")
        {:ok, _} = Nif.stmt_execute(select_stmt)
        {:ok, true} = Nif.stmt_fetch(select_stmt)
        {:ok, count} = Nif.stmt_get_query_value(select_stmt, 1)

        # Count should be 3
        count_int = if is_integer(count), do: count, else: String.to_integer(count)
        assert count_int == 3

        Nif.stmt_close(select_stmt)

        # Cleanup
        {:ok, drop_stmt} = Nif.stmt_prepare(conn, "DROP TABLE gtt_batch_test")
        Nif.stmt_execute(drop_stmt)
        Nif.stmt_close(drop_stmt)

        Nif.var_release(id_var)
        Nif.var_release(name_var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "RETURNING INTO clause" do
    @tag :oracle_database
    test "retrieves returned values from INSERT RETURNING" do
      with {:ok, ctx, conn} <- connect_test_db() do
        # Create a temporary table with a sequence-like column
        {:ok, create_stmt} = Nif.stmt_prepare(conn, """
          DECLARE
            table_exists NUMBER;
          BEGIN
            SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'GTT_RETURNING_TEST';
            IF table_exists > 0 THEN
              EXECUTE IMMEDIATE 'DROP TABLE gtt_returning_test';
            END IF;
            EXECUTE IMMEDIATE 'CREATE GLOBAL TEMPORARY TABLE gtt_returning_test (
              id NUMBER GENERATED BY DEFAULT AS IDENTITY,
              name VARCHAR2(100)
            ) ON COMMIT PRESERVE ROWS';
          END;
        """)
        {:ok, _} = Nif.stmt_execute(create_stmt)
        Nif.stmt_close(create_stmt)

        # Prepare INSERT with RETURNING
        {:ok, insert_stmt} = Nif.stmt_prepare(conn,
          "INSERT INTO gtt_returning_test (name) VALUES (:1) RETURNING id INTO :2")

        # Create variable for input name
        {:ok, name_var} = Nif.conn_new_var(conn, :varchar, :bytes, 1, 100)
        :ok = Nif.var_set_from_bytes(name_var, 0, "Test User")
        :ok = Nif.var_set_num_elements(name_var, 1)

        # Create variable for output id (for RETURNING INTO)
        {:ok, id_var} = Nif.conn_new_var(conn, :number, :int64, 1, 0)
        :ok = Nif.var_set_num_elements(id_var, 1)

        # Bind variables
        :ok = Nif.stmt_bind_by_pos(insert_stmt, 1, name_var)
        :ok = Nif.stmt_bind_by_pos(insert_stmt, 2, id_var)

        # Execute
        {:ok, _} = Nif.stmt_execute(insert_stmt)

        # Get the returned ID
        {:ok, [returned_id]} = Nif.var_get_returned_data(id_var, 0)

        # The ID should be a positive integer (auto-generated)
        assert is_integer(returned_id)
        assert returned_id > 0

        Nif.stmt_close(insert_stmt)

        # Cleanup
        {:ok, drop_stmt} = Nif.stmt_prepare(conn, "DROP TABLE gtt_returning_test")
        Nif.stmt_execute(drop_stmt)
        Nif.stmt_close(drop_stmt)

        Nif.var_release(name_var)
        Nif.var_release(id_var)
        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "retrieves multiple returned values from batch INSERT RETURNING" do
      with {:ok, ctx, conn} <- connect_test_db() do
        # Create a temporary table with identity column
        {:ok, create_stmt} = Nif.stmt_prepare(conn, """
          DECLARE
            table_exists NUMBER;
          BEGIN
            SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'GTT_BATCH_RETURNING';
            IF table_exists > 0 THEN
              EXECUTE IMMEDIATE 'DROP TABLE gtt_batch_returning';
            END IF;
            EXECUTE IMMEDIATE 'CREATE GLOBAL TEMPORARY TABLE gtt_batch_returning (
              id NUMBER GENERATED BY DEFAULT AS IDENTITY,
              name VARCHAR2(100)
            ) ON COMMIT PRESERVE ROWS';
          END;
        """)
        {:ok, _} = Nif.stmt_execute(create_stmt)
        Nif.stmt_close(create_stmt)

        # Prepare batch INSERT with RETURNING
        {:ok, insert_stmt} = Nif.stmt_prepare(conn,
          "INSERT INTO gtt_batch_returning (name) VALUES (:1) RETURNING id INTO :2")

        # Create variable for input names (3 elements)
        {:ok, name_var} = Nif.conn_new_var(conn, :varchar, :bytes, 3, 100)
        :ok = Nif.var_set_from_bytes(name_var, 0, "User1")
        :ok = Nif.var_set_from_bytes(name_var, 1, "User2")
        :ok = Nif.var_set_from_bytes(name_var, 2, "User3")
        :ok = Nif.var_set_num_elements(name_var, 3)

        # Create variable for output ids (3 elements)
        {:ok, id_var} = Nif.conn_new_var(conn, :number, :int64, 3, 0)
        :ok = Nif.var_set_num_elements(id_var, 3)

        # Bind variables
        :ok = Nif.stmt_bind_by_pos(insert_stmt, 1, name_var)
        :ok = Nif.stmt_bind_by_pos(insert_stmt, 2, id_var)

        # Execute batch
        {:ok, 0} = Nif.stmt_execute_many(insert_stmt, 3)

        # Get the returned IDs for each row
        {:ok, ids_0} = Nif.var_get_returned_data(id_var, 0)
        {:ok, ids_1} = Nif.var_get_returned_data(id_var, 1)
        {:ok, ids_2} = Nif.var_get_returned_data(id_var, 2)

        # Each should have one returned ID
        assert length(ids_0) == 1
        assert length(ids_1) == 1
        assert length(ids_2) == 1

        # All IDs should be positive
        assert Enum.at(ids_0, 0) > 0
        assert Enum.at(ids_1, 0) > 0
        assert Enum.at(ids_2, 0) > 0

        Nif.stmt_close(insert_stmt)

        # Cleanup
        {:ok, drop_stmt} = Nif.stmt_prepare(conn, "DROP TABLE gtt_batch_returning")
        Nif.stmt_execute(drop_stmt)
        Nif.stmt_close(drop_stmt)

        Nif.var_release(name_var)
        Nif.var_release(id_var)
        cleanup(ctx, conn)
      end
    end
  end

  describe "var_release/1" do
    @tag :oracle_database
    test "releases a variable" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        assert :ok = Nif.var_release(var)

        # After release, operations should fail
        result = Nif.var_set_from_bytes(var, 0, "test")
        assert {:error, "variable_released"} = result

        cleanup(ctx, conn)
      end
    end

    @tag :oracle_database
    test "releasing twice is safe" do
      with {:ok, ctx, conn} <- connect_test_db() do
        {:ok, var} = Nif.conn_new_var(conn, :varchar, :bytes, 5, 100)

        assert :ok = Nif.var_release(var)
        assert :ok = Nif.var_release(var)

        cleanup(ctx, conn)
      end
    end
  end
end
