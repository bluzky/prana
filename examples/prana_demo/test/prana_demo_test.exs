defmodule PranaDemoTest do
  use ExUnit.Case
  doctest PranaDemo

  test "greets the world" do
    assert PranaDemo.hello() == :world
  end
end
