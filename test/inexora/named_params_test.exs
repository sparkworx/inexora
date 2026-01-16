defmodule Inexora.NamedParamsTest do
  @moduledoc """
  Tests for named parameter binding functionality.

  Oracle supports two styles of parameter binding:
  1. Positional: `:1`, `:2`, `:3` - bind with a list of values
  2. Named: `:name`, `:user_id` - bind with a map of name => value

  Both styles are supported via:
  - `Nif.stmt_bind_value_by_pos/4` for positional binding
  - `Nif.stmt_bind_value_by_name/4` for named binding
  - `Nif.stmt_get_bind_names/1` to retrieve bind variable names from a statement

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

  describe "named parameter binding" do
    @tag :oracle_database
    test "binds parameter by name - :username style" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :username AS val FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, %{username: "test_value"}, [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert val == "test_value"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "binds same named parameter used multiple times" do
      with {:ok, state} <- connect_test_db() do
        # Oracle allows using the same named placeholder multiple times
        # The value is bound once and used for all occurrences
        query = Query.new("SELECT :name, :name || '_suffix' FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, %{name: "test"}, [], state)

        assert result.num_rows == 1
        assert [[val1, val2]] = result.rows
        assert val1 == "test"
        assert val2 == "test_suffix"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "binds multiple named parameters" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :first_name, :last_name, :age FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(
            query,
            %{first_name: "John", last_name: "Doe", age: 30},
            [],
            state
          )

        assert result.num_rows == 1
        assert [[first, last, age]] = result.rows
        assert first == "John"
        assert last == "Doe"
        assert Decimal.equal?(age, Decimal.new(30))

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "returns error for unknown parameter name" do
      with {:ok, state} <- connect_test_db() do
        # SQL has :username but we try to bind :user (wrong name)
        query = Query.new("SELECT :username FROM dual")

        # Binding with wrong parameter name should fail
        {:error, error, _state} =
          Connection.handle_execute(query, %{user: "test"}, [], state)

        # Should get an Oracle error about unbound variable
        assert error.message =~ "ORA-" or error.message =~ "bind"

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "named binding with atom keys" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :value FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, %{value: "atom_key_test"}, [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert val == "atom_key_test"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "named binding with string keys" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :value FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, %{"value" => "string_key_test"}, [], state)

        assert result.num_rows == 1
        assert [[val]] = result.rows
        assert val == "string_key_test"

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "named binding with NULL value" do
      with {:ok, state} <- connect_test_db() do
        query = Query.new("SELECT :val FROM dual")

        {:ok, _query, result, new_state} =
          Connection.handle_execute(query, %{val: nil}, [], state)

        assert result.num_rows == 1
        assert [[nil]] = result.rows

        Connection.disconnect(nil, new_state)
      end
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

  describe "get bind names" do
    @tag :oracle_database
    test "retrieves bind names from prepared statement" do
      with {:ok, state} <- connect_test_db() do
        alias Inexora.Nif

        {:ok, prepared_query, state} =
          Connection.handle_prepare(Query.new("SELECT :username, :age FROM dual"), [], state)

        {:ok, names} = Nif.stmt_get_bind_names(prepared_query.statement)

        # Oracle returns bind names in uppercase
        assert "USERNAME" in names
        assert "AGE" in names
        assert length(names) == 2

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "retrieves unique bind names (deduplicates)" do
      with {:ok, state} <- connect_test_db() do
        alias Inexora.Nif

        # Same parameter used multiple times - should only appear once
        {:ok, prepared_query, state} =
          Connection.handle_prepare(Query.new("SELECT :a, :a, :b FROM dual"), [], state)

        {:ok, names} = Nif.stmt_get_bind_names(prepared_query.statement)

        # Oracle deduplicates the names
        assert "A" in names
        assert "B" in names
        assert length(names) == 2

        Connection.disconnect(nil, state)
      end
    end

    @tag :oracle_database
    test "returns empty list for statement with no bind variables" do
      with {:ok, state} <- connect_test_db() do
        alias Inexora.Nif

        {:ok, prepared_query, state} =
          Connection.handle_prepare(Query.new("SELECT 1 FROM dual"), [], state)

        {:ok, names} = Nif.stmt_get_bind_names(prepared_query.statement)

        assert names == []

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
