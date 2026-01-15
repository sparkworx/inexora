defmodule Inexora do
  @moduledoc """
  Inexora - Oracle Database driver for Elixir.

  An Oracle database driver and Ecto adapter using ODPI-C
  (Oracle Database Programming Interface for C).

  ## Quick Start

  Check if the NIF is loaded and get ODPI-C version:

      iex> Inexora.odpi_version()
      {:ok, {5, 6, 4}}

  ## Requirements

  - Oracle Instant Client must be installed for database operations
  - ODPI-C version info works without Oracle client (compile-time constant)
  """

  @doc """
  Returns the ODPI-C library version.

  This is a compile-time constant and does not require Oracle Instant Client.
  """
  defdelegate odpi_version(), to: Inexora.Nif
end
