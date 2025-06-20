defmodule PranaTest do
  use ExUnit.Case
  doctest Prana

  test "greets the world" do
    assert Prana.hello() == :world
  end
end
