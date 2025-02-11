defmodule InexoraTest do
  use ExUnit.Case
  doctest Inexora

  test "greets the world" do
    assert Inexora.hello() == :world
  end
end
