defmodule Prana.Integrations.DataTest do
  use ExUnit.Case, async: false

  alias Prana.Integrations.Data

  describe "definition/0" do
    test "returns correct integration definition" do
      definition = Data.definition()

      assert definition.name == "data"
      assert definition.display_name == "Data"
      assert definition.category == "core"
      assert Map.has_key?(definition.actions, "merge")
    end
  end

  describe "merge/1" do
    test "append strategy collects inputs as array elements" do
      input_map = %{
        "strategy" => "append",
        "input_a" => %{"name" => "John", "age" => 30},
        "input_b" => %{"city" => "NYC", "status" => "active"}
      }

      assert {:ok, result, "success"} = Data.merge(input_map)

      assert result == [
               %{"name" => "John", "age" => 30},
               %{"city" => "NYC", "status" => "active"}
             ]
    end

    test "merge strategy combines object inputs" do
      input_map = %{
        "strategy" => "merge",
        "input_a" => %{"name" => "John", "age" => 30},
        "input_b" => %{"city" => "NYC", "age" => 31}
      }

      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == %{"name" => "John", "age" => 31, "city" => "NYC"}
    end

    test "concat strategy flattens array inputs" do
      input_map = %{
        "strategy" => "concat",
        "input_a" => [1, 2, 3],
        "input_b" => [4, 5]
      }

      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == [1, 2, 3, 4, 5]
    end

    test "defaults to append strategy" do
      input_map = %{
        "input_a" => %{"a" => 1},
        "input_b" => %{"b" => 2}
      }

      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == [%{"a" => 1}, %{"b" => 2}]
    end

    test "merge strategy ignores non-map inputs" do
      input_map = %{
        "strategy" => "merge",
        "input_a" => %{"name" => "John"},
        "input_b" => "invalid_data"
      }

      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == %{"name" => "John"}
    end

    test "concat strategy ignores non-array inputs" do
      input_map = %{
        "strategy" => "concat",
        "input_a" => [1, 2, 3],
        "input_b" => %{"invalid" => "data"}
      }

      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == [1, 2, 3]
    end

    test "handles nil input ports gracefully" do
      input_map = %{
        "strategy" => "append",
        "input_a" => %{"data" => "value"}
        # input_b is nil/missing
      }

      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == [%{"data" => "value"}]
    end

    test "returns error for unknown strategy" do
      input_map = %{
        "strategy" => "unknown_strategy",
        "input_a" => %{"test" => true}
      }

      assert {:error, error, "error"} = Data.merge(input_map)
      assert error.type == "merge_error"
      assert String.contains?(error.message, "unknown_strategy")
    end
  end
end
