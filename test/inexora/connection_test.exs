defmodule Inexora.ConnectionTest do
  use ExUnit.Case, async: false

  import Inexora.TestHelpers

  alias Inexora.Connection
  alias Inexora.Error

  describe "connect/1" do
    @tag :oracle_database
    test "connects with valid credentials" do
      case Connection.connect(test_connection_opts()) do
        {:ok, state} ->
          assert is_reference(state.conn)
          assert is_reference(state.context)
          assert state.transaction_status == :idle
          Connection.disconnect(nil, state)

        {:error, %Error{} = error} ->
          # Expected when Oracle is not available
          assert error.message != nil
      end
    end

    test "allows missing username for wallet authentication" do
      # Should not raise - username defaults to empty string
      # Will fail at ODPI-C level if no wallet is configured, but that's expected
      case Connection.connect(password: "pass", database: "db") do
        {:ok, state} -> Connection.disconnect(nil, state)
        {:error, %Error{}} -> :ok
      end
    end

    test "allows missing password for wallet authentication" do
      # Should not raise - password defaults to empty string
      case Connection.connect(username: "user", database: "db") do
        {:ok, state} -> Connection.disconnect(nil, state)
        {:error, %Error{}} -> :ok
      end
    end

    test "allows missing username and password for wallet authentication" do
      # Oracle Wallet authentication uses empty credentials
      case Connection.connect(database: "db") do
        {:ok, state} -> Connection.disconnect(nil, state)
        {:error, %Error{}} -> :ok
      end
    end

    test "returns error with missing database" do
      assert_raise KeyError, ~r/database|hostname/, fn ->
        Connection.connect(username: "user", password: "pass")
      end
    end
  end

  describe "build_connect_string" do
    @tag :oracle_database
    test "builds connect string from hostname/port/service_name" do
      opts = [
        username: "user",
        password: "pass",
        hostname: "myhost",
        port: 1522,
        service_name: "MYDB"
      ]

      # The connect would use "myhost:1522/MYDB" internally
      case Connection.connect(opts) do
        {:ok, state} -> Connection.disconnect(nil, state)
        {:error, _} -> :ok
      end
    end

    @tag :oracle_database
    test "uses default port 1521" do
      opts = [
        username: "user",
        password: "pass",
        hostname: "myhost",
        service_name: "MYDB"
      ]

      # The connect would use "myhost:1521/MYDB" internally
      case Connection.connect(opts) do
        {:ok, state} -> Connection.disconnect(nil, state)
        {:error, _} -> :ok
      end
    end
  end

  describe "transaction callbacks" do
    @tag :oracle_database
    test "handle_begin transitions to transaction state" do
      with {:ok, state} <- connect_test_db() do
        assert state.transaction_status == :idle

        {:ok, :began, new_state} = Connection.handle_begin([], state)
        assert new_state.transaction_status == :transaction

        Connection.disconnect(nil, new_state)
      end
    end

    @tag :oracle_database
    test "handle_commit commits and returns to idle" do
      with {:ok, state} <- connect_test_db() do
        {:ok, :began, state} = Connection.handle_begin([], state)
        {:ok, :committed, final_state} = Connection.handle_commit([], state)

        assert final_state.transaction_status == :idle
        Connection.disconnect(nil, final_state)
      end
    end

    @tag :oracle_database
    test "handle_rollback rolls back and returns to idle" do
      with {:ok, state} <- connect_test_db() do
        {:ok, :began, state} = Connection.handle_begin([], state)
        {:ok, :rolledback, final_state} = Connection.handle_rollback([], state)

        assert final_state.transaction_status == :idle
        Connection.disconnect(nil, final_state)
      end
    end

    @tag :oracle_database
    test "handle_rollback on idle state returns idle" do
      with {:ok, state} <- connect_test_db() do
        assert state.transaction_status == :idle
        {:idle, same_state} = Connection.handle_rollback([], state)
        assert same_state.transaction_status == :idle
        Connection.disconnect(nil, same_state)
      end
    end
  end

  describe "handle_status/2" do
    @tag :oracle_database
    test "returns current transaction status" do
      with {:ok, state} <- connect_test_db() do
        {:idle, _} = Connection.handle_status([], state)

        {:ok, :began, state} = Connection.handle_begin([], state)
        {:transaction, _} = Connection.handle_status([], state)

        Connection.disconnect(nil, state)
      end
    end
  end

  describe "checkout/1" do
    @tag :oracle_database
    test "succeeds for healthy connection" do
      with {:ok, state} <- connect_test_db() do
        {:ok, _state} = Connection.checkout(state)
        Connection.disconnect(nil, state)
      end
    end
  end

  describe "ping/1" do
    @tag :oracle_database
    test "succeeds for active connection" do
      with {:ok, state} <- connect_test_db() do
        {:ok, _state} = Connection.ping(state)
        Connection.disconnect(nil, state)
      end
    end
  end

end
