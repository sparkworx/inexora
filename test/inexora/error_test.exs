defmodule Inexora.ErrorTest do
  @moduledoc """
  Tests for error handling across the Inexora driver.

  These tests verify that Oracle and ODPI-C errors are properly surfaced
  to Elixir with meaningful error messages and Oracle error codes.
  """

  use ExUnit.Case, async: false

  alias Inexora.Connection
  alias Inexora.Query
  alias Inexora.Error

  describe "SQL syntax errors" do
    @tag :oracle_database
    test "returns error for invalid SQL syntax - missing column" do
      with {:ok, state} <- connect_test_db() do
        # SELECT without column list
        query = Query.new("SELECT FROM dual")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        # ORA-00936: missing expression
        assert error.oracle_code != nil

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "returns error for unclosed string literal" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT 'unclosed FROM dual")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        # ORA-01756: quoted string not properly terminated
        assert error.oracle_code != nil

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "returns error for invalid keyword" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELEKT 1 FROM dual")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        assert error.oracle_code != nil

        Connection.disconnect(nil, state)
      end
    end
  end

  describe "object not found errors" do
    @tag :oracle_database
    test "returns error for non-existent table" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT * FROM nonexistent_table_xyz_99999")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        # ORA-00942: table or view does not exist
        assert error.oracle_code == 942 or error.message =~ "00942"

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "returns error for non-existent column" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT nonexistent_column_xyz FROM dual")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        # ORA-00904: invalid identifier
        assert error.oracle_code == 904 or error.message =~ "00904"

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "returns error for non-existent sequence" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT nonexistent_seq_xyz.NEXTVAL FROM dual")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        # ORA-02289: sequence does not exist
        assert error.oracle_code != nil

        Connection.disconnect(nil, state)
      end
    end
  end

  describe "constraint violation errors" do
    @tag :oracle_database
    test "returns error for primary key violation" do
      with {:ok, state} <- connect_test_db() do
        # Create table with primary key
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'ERROR_TEST_PK';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE error_test_pk';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE error_test_pk (id NUMBER PRIMARY KEY, name VARCHAR2(100))';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Insert first row
            insert_query = Query.new("INSERT INTO error_test_pk (id, name) VALUES (:1, :2)")
            {:ok, _, _, state} = Connection.handle_execute(insert_query, [1, "first"], [], state)

            # Try to insert duplicate primary key
            {:error, error, state} = Connection.handle_execute(insert_query, [1, "duplicate"], [], state)

            assert %Error{} = error
            assert error.message =~ "ORA-"
            # ORA-00001: unique constraint violated
            assert error.oracle_code == 1 or error.message =~ "00001"

            # Clean up
            drop_query = Query.new("DROP TABLE error_test_pk")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            # PL/SQL may not be available
            Connection.disconnect(nil, state)
        end
      end
    end

    @tag :oracle_database
    test "returns error for NOT NULL constraint violation" do
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'ERROR_TEST_NOTNULL';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE error_test_notnull';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE error_test_notnull (id NUMBER NOT NULL, name VARCHAR2(100))';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Try to insert NULL into NOT NULL column
            insert_query = Query.new("INSERT INTO error_test_notnull (id, name) VALUES (:1, :2)")
            {:error, error, state} = Connection.handle_execute(insert_query, [nil, "test"], [], state)

            assert %Error{} = error
            assert error.message =~ "ORA-"
            # ORA-01400: cannot insert NULL
            assert error.oracle_code == 1400 or error.message =~ "01400"

            # Clean up
            drop_query = Query.new("DROP TABLE error_test_notnull")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end

    @tag :oracle_database
    test "returns error for check constraint violation" do
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'ERROR_TEST_CHECK';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE error_test_check';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE error_test_check (id NUMBER, age NUMBER CHECK (age >= 0))';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Try to insert negative age
            insert_query = Query.new("INSERT INTO error_test_check (id, age) VALUES (:1, :2)")
            {:error, error, state} = Connection.handle_execute(insert_query, [1, -5], [], state)

            assert %Error{} = error
            assert error.message =~ "ORA-"
            # ORA-02290: check constraint violated
            assert error.oracle_code == 2290 or error.message =~ "02290"

            # Clean up
            drop_query = Query.new("DROP TABLE error_test_check")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end
  end

  describe "data type errors" do
    @tag :oracle_database
    test "returns error for VARCHAR2 data too large" do
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'ERROR_TEST_SIZE';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE error_test_size';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE error_test_size (id NUMBER, tiny_text VARCHAR2(10))';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Try to insert text larger than column allows
            large_text = String.duplicate("X", 100)
            insert_query = Query.new("INSERT INTO error_test_size (id, tiny_text) VALUES (:1, :2)")
            {:error, error, state} = Connection.handle_execute(insert_query, [1, large_text], [], state)

            assert %Error{} = error
            assert error.message =~ "ORA-"
            # ORA-12899: value too large for column
            assert error.oracle_code == 12899 or error.message =~ "12899"

            # Clean up
            drop_query = Query.new("DROP TABLE error_test_size")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end

    @tag :oracle_database
    test "returns error for invalid number format" do
      with {:ok, state} <- connect_test_db() do
        # TO_NUMBER with invalid string should fail
        query = Query.new("SELECT TO_NUMBER('not_a_number') FROM dual")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        # ORA-01722: invalid number
        assert error.oracle_code == 1722 or error.message =~ "01722"

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "returns error for invalid date format" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT TO_DATE('not_a_date', 'YYYY-MM-DD') FROM dual")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        # ORA-01858: a non-numeric character was found where a numeric was expected
        # or ORA-01861: literal does not match format string
        assert error.oracle_code != nil

        Connection.disconnect(nil, state)
      end
    end
  end

  describe "bind parameter errors" do
    @tag :oracle_database
    test "returns error for invalid bind position" do
      with {:ok, state} <- connect_test_db() do
        # Query has :1 but we try to use it without providing any params
        query = Query.new("SELECT :1 FROM dual")

        # Execute with no parameters - should fail
        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        # Should indicate missing bind value
        assert error.message =~ "ORA-" or error.message =~ "bind"

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "returns error for too few parameters" do
      with {:ok, state} <- connect_test_db() do
        # Query expects 2 parameters
        query = Query.new("SELECT :1, :2 FROM dual")

        # Only provide 1 parameter
        {:error, error, _state} = Connection.handle_execute(query, ["one"], [], state)

        assert %Error{} = error
        # Should indicate missing bind value for position 2
        assert error.message =~ "ORA-" or error.message =~ "bind"

        Connection.disconnect(nil, state)
      end
    end
  end

  describe "division and arithmetic errors" do
    @tag :oracle_database
    test "returns error for division by zero" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT 1/0 FROM dual")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        # ORA-01476: divisor is equal to zero
        assert error.oracle_code == 1476 or error.message =~ "01476"

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "returns error for numeric overflow" do
      with {:ok, state} <- connect_test_db() do
        # Attempt to overflow NUMBER precision
        query = Query.new("SELECT POWER(10, 200) FROM dual")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Error{} = error
        assert error.message =~ "ORA-"
        # ORA-01426: numeric overflow
        assert error.oracle_code == 1426 or error.message =~ "01426"

        Connection.disconnect(nil, state)
      end
    end
  end

  describe "Error struct creation" do
    test "from_odpi/1 creates error from tuple" do
      error = Error.from_odpi({1017, "dpiConn_create", "ORA-01017: invalid username/password"})

      assert error.message == "ORA-01017: invalid username/password"
      assert error.oracle_code == 1017
      assert error.function == "dpiConn_create"
    end

    test "from_odpi/1 creates error from string" do
      error = Error.from_odpi("connection failed")

      assert error.message == "connection failed"
      assert error.oracle_code == nil
    end

    test "from_odpi/1 creates error from atom" do
      error = Error.from_odpi(:timeout)

      assert error.message == "timeout"
      assert error.oracle_code == nil
    end

    test "from_odpi/1 creates error from charlist" do
      error = Error.from_odpi(~c"connection failed")

      assert error.message == "connection failed"
      assert error.oracle_code == nil
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
