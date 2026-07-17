defmodule Inexora.NifTest do
  use ExUnit.Case, async: true

  alias Inexora.Nif

  describe "odpi_version/0" do
    test "returns the ODPI-C library version tuple" do
      assert {:ok, {major, minor, patch}} = Nif.odpi_version()
      assert is_integer(major)
      assert is_integer(minor)
      assert is_integer(patch)
      # ODPI-C version 5.x expected
      assert major >= 5
    end
  end

  describe "context_create/0" do
    @tag :oracle_client
    test "creates a context when Oracle client is available" do
      case Nif.context_create() do
        {:ok, ctx} ->
          assert is_reference(ctx)
          assert Nif.context_destroy(ctx) == :ok

        {:error, %{code: code, fn_name: fn_name, message: message}} ->
          # Expected error when Oracle Instant Client is not installed
          assert is_integer(code)
          assert is_binary(fn_name) or is_list(fn_name)
          assert is_binary(message) or is_list(message)
      end
    end
  end

  describe "context_create/1" do
    @tag :oracle_client
    test "creates a context with empty options" do
      case Nif.context_create([]) do
        {:ok, ctx} ->
          assert is_reference(ctx)
          assert Nif.context_destroy(ctx) == :ok

        {:error, %{code: code, fn_name: fn_name, message: message}} ->
          # Expected error when Oracle Instant Client is not installed
          assert is_integer(code)
          assert is_binary(fn_name) or is_list(fn_name)
          assert is_binary(message) or is_list(message)
      end
    end

    @tag :oracle_client
    test "creates a context with custom driver name" do
      case Nif.context_create(driver_name: "TestApp : 1.0.0") do
        {:ok, ctx} ->
          assert is_reference(ctx)
          assert Nif.context_destroy(ctx) == :ok

        {:error, %{code: code, fn_name: fn_name, message: message}} ->
          # Expected error when Oracle Instant Client is not installed
          assert is_integer(code)
          assert is_binary(fn_name) or is_list(fn_name)
          assert is_binary(message) or is_list(message)
      end
    end

    @tag :oracle_client
    test "creates a context with all options" do
      opts = [
        driver_name: "TestApp : 2.0.0",
        oracle_client_lib_dir: "/nonexistent/path",
        oracle_client_config_dir: "/nonexistent/config"
      ]

      # This may fail due to invalid paths, but the options parsing should work
      case Nif.context_create(opts) do
        {:ok, ctx} ->
          assert is_reference(ctx)
          Nif.context_destroy(ctx)

        {:error, %{code: code}} ->
          # Error is expected (invalid paths or no Oracle client)
          assert is_integer(code)
      end
    end

    test "returns error for invalid driver_name type" do
      assert {:error, "driver_name_must_be_binary"} = Nif.context_create(driver_name: 123)
    end

    test "returns error for invalid oracle_client_lib_dir type" do
      assert {:error, "oracle_client_lib_dir_must_be_binary"} =
               Nif.context_create(oracle_client_lib_dir: :invalid)
    end

    test "returns error for invalid oracle_client_config_dir type" do
      assert {:error, "oracle_client_config_dir_must_be_binary"} =
               Nif.context_create(oracle_client_config_dir: 456)
    end

    @tag :oracle_client
    test "ignores unknown options for forward compatibility" do
      case Nif.context_create(unknown_option: "value", another: 123) do
        {:ok, ctx} ->
          assert is_reference(ctx)
          Nif.context_destroy(ctx)

        {:error, %{code: code}} ->
          # Error from Oracle client, not from option parsing
          assert is_integer(code)
      end
    end
  end

  describe "context_destroy/1" do
    @tag :oracle_client
    test "destroys a valid context" do
      case Nif.context_create() do
        {:ok, ctx} ->
          assert Nif.context_destroy(ctx) == :ok
          # Second destroy should still work (idempotent)
          assert Nif.context_destroy(ctx) == :ok

        {:error, _} ->
          # Skip if Oracle client not available
          :ok
      end
    end
  end
end
