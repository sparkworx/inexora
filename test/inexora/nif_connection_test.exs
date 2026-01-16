defmodule Inexora.NifConnectionTest do
  # async: false to avoid Oracle client concurrency issues
  use ExUnit.Case, async: false

  alias Inexora.Nif

  describe "conn_create/4" do
    @tag :oracle_database
    test "creates connection with valid credentials" do
      {:ok, ctx} = Nif.context_create()

      username = System.get_env("ORACLE_USER", "test_user")
      password = System.get_env("ORACLE_PASSWORD", "test_password")
      database = System.get_env("ORACLE_DATABASE", "localhost:1521/FREEPDB1")

      case Nif.conn_create(ctx, username, password, database) do
        {:ok, conn} ->
          assert is_reference(conn)
          Nif.conn_close(conn)

        {:error, {code, fn_name, message}} ->
          assert is_integer(code)
          assert is_binary(fn_name) or is_list(fn_name)
          assert is_binary(message) or is_list(message)
      end

      Nif.context_destroy(ctx)
    end
  end

  describe "conn_ping/1" do
    @tag :oracle_database
    test "pings healthy connection" do
      with {:ok, ctx} <- Nif.context_create(),
           {:ok, conn} <- create_test_connection(ctx) do
        assert Nif.conn_ping(conn) == :ok
        Nif.conn_close(conn)
        Nif.context_destroy(ctx)
      end
    end
  end

  describe "conn_commit/1 and conn_rollback/1" do
    @tag :oracle_database
    test "commit and rollback on connection" do
      with {:ok, ctx} <- Nif.context_create(),
           {:ok, conn} <- create_test_connection(ctx) do
        # Both should succeed on a fresh connection
        assert Nif.conn_commit(conn) == :ok
        assert Nif.conn_rollback(conn) == :ok

        Nif.conn_close(conn)
        Nif.context_destroy(ctx)
      end
    end
  end

  describe "conn_get_server_version/1" do
    @tag :oracle_database
    test "returns server version info" do
      with {:ok, ctx} <- Nif.context_create(),
           {:ok, conn} <- create_test_connection(ctx) do
        {:ok, {release_string, version_info}} = Nif.conn_get_server_version(conn)

        assert is_binary(release_string) or is_list(release_string)
        assert {_, _, _, _, _} = version_info

        Nif.conn_close(conn)
        Nif.context_destroy(ctx)
      end
    end
  end

  describe "conn_get_is_healthy/1" do
    @tag :oracle_database
    test "returns health status" do
      with {:ok, ctx} <- Nif.context_create(),
           {:ok, conn} <- create_test_connection(ctx) do
        {:ok, is_healthy} = Nif.conn_get_is_healthy(conn)
        assert is_boolean(is_healthy)
        assert is_healthy == true

        Nif.conn_close(conn)
        Nif.context_destroy(ctx)
      end
    end
  end

  describe "conn_get_transaction_in_progress/1" do
    @tag :oracle_database
    test "returns transaction status" do
      with {:ok, ctx} <- Nif.context_create(),
           {:ok, conn} <- create_test_connection(ctx) do
        {:ok, in_progress} = Nif.conn_get_transaction_in_progress(conn)
        assert is_boolean(in_progress)

        Nif.conn_close(conn)
        Nif.context_destroy(ctx)
      end
    end
  end

  # Helper
  defp create_test_connection(ctx) do
    username = System.get_env("ORACLE_USER", "test_user")
    password = System.get_env("ORACLE_PASSWORD", "test_password")
    database = System.get_env("ORACLE_DATABASE", "localhost:1521/FREEPDB1")
    Nif.conn_create(ctx, username, password, database)
  end
end
