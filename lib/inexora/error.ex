defmodule Inexora.Error do
  @moduledoc """
  Exception struct for Inexora database errors.

  This module provides a consistent error type for all errors
  originating from ODPI-C and Oracle database operations.

  Database errors carry the full ODPI-C `dpiErrorInfo` detail:

      %Inexora.Error{
        message: "ORA-01017: invalid username/password",
        oracle_code: 1017,
        function: "dpiConn_create",
        action: nil,
        sql_state: "72000",
        offset: 0,
        recoverable: false,
        warning: false
      }

  > #### About `:recoverable` {: .warning}
  >
  > `dpiErrorInfo.isRecoverable` is only meaningful when **both** the Oracle
  > client and server are release 12.1 or higher; it is reported `false`
  > otherwise. Treat `recoverable: false` as "unknown", not as proof that the
  > connection is dead.

  ## Public interface (frozen contract)

  `%Inexora.Error{}` is the sole error shape the `ecto_oracle` adapter reads.
  The frozen contract is the `oracle_code` and `message` fields (the adapter
  keys constraint mapping off `oracle_code` in its `to_constraints`); the
  remaining `dpiErrorInfo` fields are additional detail, not part of the
  contract. See `docs/adapter-split-plan.md` for the full driver interface.
  """

  defexception [
    :message,
    :oracle_code,
    :function,
    :action,
    :sql_state,
    :offset,
    :recoverable,
    :warning
  ]

  @type t :: %__MODULE__{
          message: String.t(),
          oracle_code: integer() | nil,
          function: String.t() | nil,
          action: String.t() | nil,
          sql_state: String.t() | nil,
          offset: non_neg_integer() | nil,
          recoverable: boolean() | nil,
          warning: boolean() | nil
        }

  @impl true
  def message(%__MODULE__{message: message}), do: message

  @doc """
  Creates an error from an ODPI-C error payload or a simple reason.

  ODPI-C database errors are surfaced from the NIF as a map carrying the full
  `dpiErrorInfo` detail (`:code`, `:fn_name`, `:message`, `:action`,
  `:sql_state`, `:offset`, `:recoverable`, `:warning`). The legacy
  `{code, function, message}` tuple form is still accepted for backward
  compatibility. Platform/runtime errors arrive as a string, atom, or charlist
  reason and only populate `:message`.

  ## Examples

      iex> error = Inexora.Error.from_odpi("connection failed")
      iex> error.message
      "connection failed"

      iex> info = %{code: 1017, fn_name: "dpiConn_create",
      ...>          message: "ORA-01017: invalid username/password",
      ...>          action: nil, sql_state: "72000", offset: 0,
      ...>          recoverable: false, warning: false}
      iex> error = Inexora.Error.from_odpi(info)
      iex> {error.oracle_code, error.sql_state, error.recoverable}
      {1017, "72000", false}
  """
  @spec from_odpi(
          Inexora.Nif.odpi_error()
          | {integer(), String.t() | charlist(), String.t() | charlist()}
          | String.t()
          | atom()
          | charlist()
        ) :: t()
  def from_odpi(%{code: code, message: message} = info) when is_integer(code) do
    %__MODULE__{
      message: to_string(message || "unknown error"),
      oracle_code: code,
      function: nilable_string(info[:fn_name]),
      action: nilable_string(info[:action]),
      sql_state: nilable_string(info[:sql_state]),
      offset: info[:offset],
      recoverable: info[:recoverable],
      warning: info[:warning]
    }
  end

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

  defp nilable_string(nil), do: nil
  defp nilable_string(value), do: to_string(value)
end
