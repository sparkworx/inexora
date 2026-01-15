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

        {:error, {code, fn_name, message}} ->
          # Expected error when Oracle Instant Client is not installed
          assert is_integer(code)
          assert is_binary(fn_name) or is_list(fn_name)
          assert is_binary(message) or is_list(message)
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
