defmodule PranaDemoTest do
  use ExUnit.Case
  doctest PranaDemo

  test "can start and stop demo" do
    assert PranaDemo.start() == :ok
    assert PranaDemo.stop() == :ok
  end
end
