defmodule Inexora.Error do
  @moduledoc """
  Exception struct for Inexora database errors.

  This module provides a consistent error type for all errors
  originating from ODPI-C and Oracle database operations.
  """

  defexception [:message, :oracle_code, :function, :action]

  @type t :: %__MODULE__{
          message: String.t(),
          oracle_code: integer() | nil,
          function: String.t() | nil,
          action: String.t() | nil
        }

  @impl true
  def message(%__MODULE__{message: message}), do: message

  @doc """
  Creates an error from an ODPI-C error tuple or simple reason.

  ODPI-C errors are returned as `{code, function_name, message}` tuples.
  Simple reasons can be strings, atoms, or charlists.

  ## Examples

      iex> Inexora.Error.from_odpi({1017, "dpiConn_create", "ORA-01017: invalid username/password"})
      %Inexora.Error{message: "ORA-01017: invalid username/password", oracle_code: 1017, function: "dpiConn_create"}

      iex> Inexora.Error.from_odpi("connection failed")
      %Inexora.Error{message: "connection failed"}
  """
  @spec from_odpi(
          {integer(), String.t() | charlist(), String.t() | charlist()}
          | String.t()
          | atom()
          | charlist()
        ) :: t()
  def from_odpi({code, function, message}) when is_integer(code) do
    %__MODULE__{
      message: to_string(message),
      oracle_code: code,
      function: to_string(function),
      action: nil
    }
  end

  def from_odpi(reason) when is_binary(reason) do
    %__MODULE__{message: reason}
  end

  def from_odpi(reason) when is_atom(reason) do
    %__MODULE__{message: Atom.to_string(reason)}
  end

  def from_odpi(reason) when is_list(reason) do
    %__MODULE__{message: to_string(reason)}
  end
end
