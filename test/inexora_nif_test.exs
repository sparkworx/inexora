defmodule InexoraNIFTest do
  use ExUnit.Case

  test "NIF greets world" do
    assert InexoraNIF.hello() == ~c"world"
  end
end
