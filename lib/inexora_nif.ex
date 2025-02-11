defmodule InexoraNIF do
  @moduledoc """
  Documentation for `InexoraNIF`.
  """

  @compile {:autoload, false}
  @on_load {:load_nif, 0}

  def load_nif do
    path = :filename.join(:code.priv_dir(:inexora), ~c"inexora_nif")
    :ok = :erlang.load_nif(path, 0)
  end

  def hello(), do: :erlang.nif_error(:nif_not_loaded)
  def create_context(_opts \\ []), do: :erlang.nif_error(:nif_not_loaded)
end
