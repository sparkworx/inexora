defmodule Inexora.Nif do
  @moduledoc """
  Low-level NIF bindings to ODPI-C.

  This module provides the raw NIF function stubs that interface
  with the ODPI-C library. Higher-level APIs should be built on top.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    path = :filename.join(:code.priv_dir(:inexora), ~c"inexora_nif")
    :erlang.load_nif(path, 0)
  end

  @type context :: reference()
  @type reason :: atom() | String.t() | {integer(), String.t(), String.t()}

  @doc """
  Returns the ODPI-C library version as a tuple.

  This function does NOT require Oracle Instant Client to be installed.

  ## Examples

      iex> Inexora.Nif.odpi_version()
      {:ok, {5, 6, 4}}
  """
  @spec odpi_version() :: {:ok, {integer(), integer(), integer()}} | {:error, reason()}
  def odpi_version, do: :erlang.nif_error(:not_loaded)

  @doc """
  Creates a new ODPI-C context.

  Note: This will fail if Oracle Instant Client is not installed and
  accessible in the library path.

  ## Examples

      iex> {:ok, ctx} = Inexora.Nif.context_create()
      iex> is_reference(ctx)
      true
  """
  @spec context_create() :: {:ok, context()} | {:error, reason()}
  def context_create, do: :erlang.nif_error(:not_loaded)

  @doc """
  Destroys a ODPI-C context.

  ## Examples

      iex> {:ok, ctx} = Inexora.Nif.context_create()
      iex> Inexora.Nif.context_destroy(ctx)
      :ok
  """
  @spec context_destroy(context()) :: :ok | {:error, reason()}
  def context_destroy(_context), do: :erlang.nif_error(:not_loaded)

  @doc """
  Gets the Oracle client version.

  Requires a valid context and Oracle Instant Client installed.
  Returns `{version, release, update, port_release, port_update}`.

  ## Examples

      iex> {:ok, ctx} = Inexora.Nif.context_create()
      iex> {:ok, {major, _, _, _, _}} = Inexora.Nif.get_client_version(ctx)
      iex> major >= 11
      true
  """
  @spec get_client_version(context()) ::
          {:ok, {integer(), integer(), integer(), integer(), integer()}} | {:error, reason()}
  def get_client_version(_context), do: :erlang.nif_error(:not_loaded)
end
