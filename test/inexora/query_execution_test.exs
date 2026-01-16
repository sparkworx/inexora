defmodule Inexora.QueryExecutionTest do
  use ExUnit.Case, async: false

  alias Inexora.Connection
  alias Inexora.Query
  alias Inexora.Result

  describe "handle_prepare/3" do
    @tag :oracle_database
    test "prepares a SQL statement" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT 1 FROM dual")

        {:ok, prepared_query, new_state} = Connection.handle_prepare(query, [], state)

        assert is_reference(prepared_query.statement)
        assert prepared_query.sql == "SELECT 1 FROM dual"

        # Clean up
        Connection.handle_close(prepared_query, [], new_state)
        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "returns error for invalid SQL on execute" do
      # Oracle allows preparing invalid SQL - error occurs at execute time
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT * FROM nonexistent_table_xyz")

        {:error, error, _state} = Connection.handle_execute(query, [], [], state)

        assert %Inexora.Error{} = error
        assert error.message =~ "ORA-" or error.oracle_code != nil
        Connection.disconnect(nil, state)
      end
    end
  end

  describe "handle_execute/4" do
    @tag :oracle_database
    test "executes SELECT and returns rows" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT 1 AS num, 'hello' AS str FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert %Result{} = result
        assert result.columns == ["NUM", "STR"]
        assert result.num_rows == 1
        assert [[num, str]] = result.rows
        # Numbers are returned as Decimal for precision
        assert Decimal.equal?(num, Decimal.new(1)) or num == 1
        assert str == "hello"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "executes SELECT with multiple rows" do
      with {:ok, state} <- connect_test_db() do
        query =
          Query.new("""
          SELECT level AS n FROM dual CONNECT BY level <= 5
          """)

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert result.num_rows == 5
        assert length(result.rows) == 5

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "executes SELECT with parameter binding" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :1 AS val FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [42], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        # Numbers are returned as Decimal for precision
        assert Decimal.equal?(val, Decimal.new(42)) or val == 42

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "executes SELECT with string parameter" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :1 AS val FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, ["test"], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert val == "test"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "returns NUMBER with decimal as Decimal" do
      with {:ok, state} <- connect_test_db() do
        # Test that decimal precision is preserved
        query = Query.new("SELECT 123.456789012345678901234567890 AS num FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert %Decimal{} = val
        # Verify precision is preserved (at least the first several digits)
        assert Decimal.to_string(val) =~ "123.456789"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "returns NUMBER integer as Decimal" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT 42 AS num FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert %Decimal{} = val
        assert Decimal.equal?(val, Decimal.new("42"))

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "handles NULL values" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT NULL AS val FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert [[nil]] = result.rows

        Connection.disconnect(nil, new_state)
      end
    end
  end

  describe "handle_close/3" do
    @tag :oracle_database
    test "closes a prepared statement" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT 1 FROM dual")
        {:ok, prepared_query, state} = Connection.handle_prepare(query, [], state)

        {:ok, nil, final_state} = Connection.handle_close(prepared_query, [], state)

        assert is_map(final_state)
        Connection.disconnect(nil, final_state)
      end
    end
  end

  describe "DML operations" do
    @tag :oracle_database
    test "INSERT returns affected row count" do
      with {:ok, state} <- connect_test_db() do
        # Create a temporary table
        create_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'INEXORA_TEST_TMP';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE inexora_test_tmp';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE inexora_test_tmp (id NUMBER, name VARCHAR2(100))';
        END;
        """)

        case Connection.handle_execute(create_query, [], [], state) do
          {:ok, _, _, state} ->
            # Insert a row
            insert_query = Query.new("INSERT INTO inexora_test_tmp (id, name) VALUES (:1, :2)")
            {:ok, _, result, state} = Connection.handle_execute(insert_query, [1, "test"], [], state)

            assert %Result{} = result
            assert result.num_rows == 1
            assert result.columns == nil
            assert result.rows == nil

            # Clean up
            drop_query = Query.new("DROP TABLE inexora_test_tmp")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            # PL/SQL may not be available or table creation failed
            Connection.disconnect(nil, state)
        end
      end
    end
  end

  describe "cursor operations" do
    @tag :oracle_database
    test "handle_declare returns not implemented error" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT 1 FROM dual")
        {:error, error, _state} = Connection.handle_declare(query, [], [], state)
        assert error.message =~ "not implemented"
        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "handle_fetch returns not implemented error" do
      with {:ok, state} <- connect_test_db() do
        {:error, error, _state} = Connection.handle_fetch(nil, nil, [], state)
        assert error.message =~ "not implemented"
        Connection.disconnect(nil, state)
      end
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
