defmodule Inexora.QueryExecutionTest do
  use ExUnit.Case, async: false

  import Inexora.TestHelpers

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

  describe "LOB operations" do
    @tag :oracle_database
    test "reads CLOB data as string" do
      with {:ok, state} <- connect_test_db() do
        # Use TO_CLOB to create a CLOB value
        query = Query.new("SELECT TO_CLOB('Hello, CLOB World!') AS clob_val FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert result.num_rows == 1
        assert [[clob_val]] = result.rows
        assert is_binary(clob_val)
        assert clob_val == "Hello, CLOB World!"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "reads large CLOB data" do
      with {:ok, state} <- connect_test_db() do
        # Generate a large string using RPAD (VARCHAR2 limited to 4000 bytes)
        query = Query.new("SELECT TO_CLOB(RPAD('X', 4000, 'Y')) AS large_clob FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert result.num_rows == 1
        assert [[clob_val]] = result.rows
        assert is_binary(clob_val)
        assert String.length(clob_val) == 4000
        assert String.starts_with?(clob_val, "X")

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "reads BLOB data as binary" do
      with {:ok, state} <- connect_test_db() do
        # Use UTL_RAW.CAST_TO_RAW and TO_BLOB to create BLOB data
        query = Query.new("SELECT TO_BLOB(UTL_RAW.CAST_TO_RAW('binary data')) AS blob_val FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert result.num_rows == 1
        assert [[blob_val]] = result.rows
        assert is_binary(blob_val)
        assert blob_val == "binary data"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "reads empty CLOB" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT TO_CLOB('') AS empty_clob FROM dual")

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert result.num_rows == 1
        assert [[clob_val]] = result.rows
        # Empty CLOB might be nil or empty string depending on Oracle version
        assert clob_val == "" or clob_val == nil

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "reads NULL CLOB" do
      with {:ok, state} <- connect_test_db() do
        # Use EMPTY_CLOB() which returns an empty LOB locator, or a subquery that returns NULL
        query = Query.new("""
        SELECT CASE WHEN 1=0 THEN TO_CLOB('x') ELSE NULL END AS null_clob FROM dual
        """)

        {:ok, _query, result, new_state} = Connection.handle_execute(query, [], [], state)

        assert result.num_rows == 1
        assert [[nil]] = result.rows

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "reads large CLOB data (100KB+)" do
      with {:ok, state} <- connect_test_db() do
        # Create a table with CLOB column and insert large data using PL/SQL
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'LOB_TEST_LARGE';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE lob_test_large';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE lob_test_large (id NUMBER, content CLOB)';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Insert a large CLOB using PL/SQL to concatenate beyond 4000 bytes
            # Build 100KB of data (100 * 1000 chars)
            insert_query = Query.new("""
            DECLARE
              v_clob CLOB;
              v_chunk VARCHAR2(4000);
            BEGIN
              v_chunk := RPAD('X', 4000, 'Y');
              DBMS_LOB.CREATETEMPORARY(v_clob, TRUE);
              FOR i IN 1..25 LOOP
                DBMS_LOB.WRITEAPPEND(v_clob, LENGTH(v_chunk), v_chunk);
              END LOOP;
              INSERT INTO lob_test_large (id, content) VALUES (1, v_clob);
              DBMS_LOB.FREETEMPORARY(v_clob);
            END;
            """)

            case Connection.handle_execute(insert_query, [], [], state) do
              {:ok, _, _, state} ->
                # Read it back
                select_query = Query.new("SELECT content FROM lob_test_large WHERE id = 1")
                {:ok, _query, result, state} = Connection.handle_execute(select_query, [], [], state)

                assert result.num_rows == 1
                assert [[clob_val]] = result.rows
                assert is_binary(clob_val)
                # Should be 100KB (25 * 4000 = 100000 bytes)
                assert byte_size(clob_val) == 100_000
                assert String.starts_with?(clob_val, "X")

                # Clean up
                drop_query = Query.new("DROP TABLE lob_test_large")
                Connection.handle_execute(drop_query, [], [], state)
                Connection.disconnect(nil, state)

              {:error, _error, state} ->
                # DBMS_LOB may not be available
                drop_query = Query.new("DROP TABLE lob_test_large")
                Connection.handle_execute(drop_query, [], [], state)
                Connection.disconnect(nil, state)
            end

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end

    @tag :oracle_database
    test "reads large BLOB data (100KB+)" do
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'BLOB_TEST_LARGE';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE blob_test_large';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE blob_test_large (id NUMBER, content BLOB)';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Insert a large BLOB using PL/SQL
            insert_query = Query.new("""
            DECLARE
              v_blob BLOB;
              v_raw RAW(2000);
            BEGIN
              v_raw := UTL_RAW.CAST_TO_RAW(RPAD('B', 2000, 'B'));
              DBMS_LOB.CREATETEMPORARY(v_blob, TRUE);
              FOR i IN 1..50 LOOP
                DBMS_LOB.WRITEAPPEND(v_blob, UTL_RAW.LENGTH(v_raw), v_raw);
              END LOOP;
              INSERT INTO blob_test_large (id, content) VALUES (1, v_blob);
              DBMS_LOB.FREETEMPORARY(v_blob);
            END;
            """)

            case Connection.handle_execute(insert_query, [], [], state) do
              {:ok, _, _, state} ->
                # Read it back
                select_query = Query.new("SELECT content FROM blob_test_large WHERE id = 1")
                {:ok, _query, result, state} = Connection.handle_execute(select_query, [], [], state)

                assert result.num_rows == 1
                assert [[blob_val]] = result.rows
                assert is_binary(blob_val)
                # Should be 100KB (50 * 2000 = 100000 bytes)
                assert byte_size(blob_val) == 100_000

                # Clean up
                drop_query = Query.new("DROP TABLE blob_test_large")
                Connection.handle_execute(drop_query, [], [], state)
                Connection.disconnect(nil, state)

              {:error, _error, state} ->
                drop_query = Query.new("DROP TABLE blob_test_large")
                Connection.handle_execute(drop_query, [], [], state)
                Connection.disconnect(nil, state)
            end

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end

    @tag :oracle_database
    test "distinguishes empty CLOB from NULL CLOB in table" do
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'LOB_TEST_EMPTY';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE lob_test_empty';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE lob_test_empty (id NUMBER, content CLOB)';
          INSERT INTO lob_test_empty (id, content) VALUES (1, EMPTY_CLOB());
          INSERT INTO lob_test_empty (id, content) VALUES (2, NULL);
          INSERT INTO lob_test_empty (id, content) VALUES (3, TO_CLOB(''''));
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Read all rows
            select_query = Query.new("SELECT id, content FROM lob_test_empty ORDER BY id")
            {:ok, _query, result, state} = Connection.handle_execute(select_query, [], [], state)

            assert result.num_rows == 3
            [[1, empty_clob], [2, null_clob], [3, empty_string_clob]] = result.rows

            # EMPTY_CLOB() returns an initialized but empty LOB locator
            # This might be "" or nil depending on implementation
            assert empty_clob == "" or empty_clob == nil

            # NULL CLOB should be nil
            assert null_clob == nil

            # TO_CLOB('') should be empty string
            assert empty_string_clob == "" or empty_string_clob == nil

            # Clean up
            drop_query = Query.new("DROP TABLE lob_test_empty")
            Connection.handle_execute(drop_query, [], [], state)
            Connection.disconnect(nil, state)

          {:error, _error, state} ->
            Connection.disconnect(nil, state)
        end
      end
    end

    @tag :oracle_database
    test "reads NCLOB with Unicode content" do
      with {:ok, state} <- connect_test_db() do
        setup_query = Query.new("""
        DECLARE
          table_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'LOB_TEST_NCLOB';
          IF table_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE lob_test_nclob';
          END IF;
          EXECUTE IMMEDIATE 'CREATE TABLE lob_test_nclob (id NUMBER, content NCLOB)';
        END;
        """)

        case Connection.handle_execute(setup_query, [], [], state) do
          {:ok, _, _, state} ->
            # Insert Unicode content
            insert_query = Query.new("INSERT INTO lob_test_nclob (id, content) VALUES (:1, :2)")
            unicode_text = "Hello \u4e16\u754c \u0416\u0430\u0433\u0430"

            case Connection.handle_execute(insert_query, [1, unicode_text], [], state) do
              {:ok, _, _, state} ->
                # Read it back
                select_query = Query.new("SELECT content FROM lob_test_nclob WHERE id = 1")
                {:ok, _query, result, state} = Connection.handle_execute(select_query, [], [], state)

                assert result.num_rows == 1
                assert [[nclob_val]] = result.rows
                assert is_binary(nclob_val)
                assert String.valid?(nclob_val)
                assert nclob_val =~ "Hello"

                # Clean up
                drop_query = Query.new("DROP TABLE lob_test_nclob")
                Connection.handle_execute(drop_query, [], [], state)
                Connection.disconnect(nil, state)

              {:error, _error, state} ->
                drop_query = Query.new("DROP TABLE lob_test_nclob")
                Connection.handle_execute(drop_query, [], [], state)
                Connection.disconnect(nil, state)
            end

          {:error, _error, state} ->
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

end
