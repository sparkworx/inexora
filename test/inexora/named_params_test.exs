defmodule Inexora.NamedParamsTest do
  @moduledoc """
  Tests for named parameter binding functionality.

  Oracle supports two styles of parameter binding:
  1. Positional: `:1`, `:2`, `:3` - Currently supported
  2. Named: `:name`, `:user_id` - NOT YET SUPPORTED

  ODPI-C provides `dpiStmt_bindValueByName()` for named binding, but the Inexora
  NIF currently only implements `stmt_bind_value_by_pos()`.

  These tests document the current behavior and provide a framework for when
  named parameter support is added.

  See ODPI-C test_4100 and test_2100 for reference implementation.
  """

  use ExUnit.Case, async: false

  alias Inexora.Connection
  alias Inexora.Query

  describe "positional parameter binding (currently supported)" do
    @tag :oracle_database
    test "binds single positional parameter" do
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
    test "binds multiple positional parameters" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :1, :2, :3 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, ["first", "second", "third"], [], state)

        assert result.num_rows == 1
        assert [[first, second, third]] = result.rows
        assert first == "first"
        assert second == "second"
        assert third == "third"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "binds same positional parameter used multiple times" do
      with {:ok, state} <- connect_test_db() do
        # Oracle allows using the same positional placeholder multiple times
        # The value is bound once and used for all occurrences
        query = Query.new("SELECT :1, :1 || '_suffix' FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, ["test"], [], state)

        assert result.num_rows == 1
        assert [[val1, val2]] = result.rows
        assert val1 == "test"
        assert val2 == "test_suffix"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "binds positional parameters with different types" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :1, :2, :3 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, ["string", 42, 3.14], [], state)

        assert result.num_rows == 1
        assert [[str_val, int_val, float_val]] = result.rows
        assert str_val == "string"
        assert Decimal.equal?(int_val, Decimal.new(42))
        assert is_float(float_val) or match?(%Decimal{}, float_val)

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "binds NULL value positionally" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :1 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, [nil], [], state)

        assert result.num_rows == 1
        assert [[nil]] = result.rows

        Connection.disconnect(nil, new_state)
      end
    end
  end

  describe "named parameter binding (requires NIF support)" do
    # These tests document the expected behavior once named binding is supported.
    # Currently skipped as they require NIF changes (stmt_bind_value_by_name).

    @tag :oracle_database
    @tag :skip
    test "binds parameter by name - :username style" do
      # This test documents the expected behavior once named binds are supported
      # SQL would be: "SELECT :username FROM dual"
      # Bind would map "username" => "test_value"

      # Currently, Oracle will parse the named placeholder but we can't bind to it
      # without NIF support for dpiStmt_bindValueByName

      with {:ok, state} <- connect_test_db() do
        # This would require named binding support:
        # query = Query.new("SELECT :username FROM dual")
        # {:ok, _query, result, state} = Connection.handle_execute(query, %{username: "test"}, [], state)

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    @tag :skip
    test "binds same named parameter used multiple times" do
      # SQL: "SELECT * FROM users WHERE name = :name OR email LIKE :name || '%'"
      # Named binding should bind the value once and Oracle uses it for all occurrences
      assert true
    end

    @tag :oracle_database
    @tag :skip
    test "binds multiple named parameters" do
      # SQL: "SELECT :first_name, :last_name, :age FROM dual"
      # Bind map: %{first_name: "John", last_name: "Doe", age: 30}
      assert true
    end

    @tag :oracle_database
    @tag :skip
    test "returns error for unknown parameter name" do
      # SQL has :username but we try to bind :user
      # Should return an error about unbound variable
      assert true
    end
  end

  describe "mixed parameter styles" do
    @tag :oracle_database
    test "Oracle does not allow mixing positional and named placeholders" do
      # Oracle doesn't allow mixing :1 style with :name style in the same statement
      # This is a documentation test to confirm the behavior

      with {:ok, state} <- connect_test_db() do
        # This SQL has both :1 (positional) and :name (named)
        # Oracle should reject this at parse/execute time
        query = Query.new("SELECT :1, :name FROM dual")

        # Note: The actual error depends on Oracle version and how it's handled
        # Some versions may allow it if the named parameter happens to match a position
        {:error, error, _state} = Connection.handle_execute(query, ["val"], [], state)

        assert error.message =~ "ORA-" or error.message =~ "bind"

        Connection.disconnect(nil, state)
      end
    end
  end

  describe "parameter binding edge cases" do
    @tag :oracle_database
    test "handles empty string parameter" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :1 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, [""], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        # Oracle treats empty string as NULL in some contexts
        assert val == "" or val == nil

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "handles very long string parameter" do
      with {:ok, state} <- connect_test_db() do
        # Test with string just under VARCHAR2 limit (4000 bytes)
        long_string = String.duplicate("X", 4000)
        query = Query.new("SELECT :1 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, [long_string], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert val == long_string

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "handles special characters in string parameter" do
      with {:ok, state} <- connect_test_db() do
        special_string = "Test with 'quotes' and \"double quotes\" and \\ backslash"
        query = Query.new("SELECT :1 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, [special_string], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert val == special_string

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "handles Unicode in string parameter" do
      with {:ok, state} <- connect_test_db() do
        unicode_string = "Hello \u4e16\u754c \u0416\u0430\u0433\u0430 \u00e9\u00e0\u00fc"
        query = Query.new("SELECT :1 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, [unicode_string], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert val == unicode_string

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "handles large integer parameter" do
      with {:ok, state} <- connect_test_db() do
        large_int = 9_223_372_036_854_775_807  # Max int64
        query = Query.new("SELECT :1 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, [large_int], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert Decimal.equal?(val, Decimal.new(large_int))

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "handles negative number parameter" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :1 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, [-42], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert Decimal.equal?(val, Decimal.new(-42))

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "handles decimal/float parameter" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :1 FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, [123.456], [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        # Float parameters may return as Decimal or float depending on precision
        assert is_float(val) or match?(%Decimal{}, val)

        Connection.disconnect(nil, new_state)
      end
    end
  end

  describe "get bind names (requires NIF support)" do
    # ODPI-C provides dpiStmt_getBindNames() to retrieve the names of bind
    # variables in a prepared statement. This is useful for named binding.

    @tag :oracle_database
    @tag :skip
    test "retrieves bind names from prepared statement" do
      # This would require NIF support for stmt_get_bind_names
      # SQL: "SELECT :username, :age FROM dual"
      # Expected bind names: ["USERNAME", "AGE"] (Oracle uppercases)
      assert true
    end

    @tag :oracle_database
    @tag :skip
    test "retrieves unique bind names (deduplicates)" do
      # SQL: "SELECT :a, :a, :b FROM dual"
      # Expected bind names: ["A", "B"] (deduplicated)
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
