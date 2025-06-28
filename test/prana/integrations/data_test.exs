defmodule Prana.Integrations.DataTest do
  use ExUnit.Case, async: true

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
    test "combine_objects strategy merges maps" do
      input_map = %{
        "strategy" => "combine_objects",
        "inputs" => [
          %{"name" => "John", "age" => 30},
          %{"city" => "NYC", "age" => 31}
        ]
      }
      
      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == %{"name" => "John", "age" => 31, "city" => "NYC"}
    end

    test "combine_arrays strategy flattens arrays" do
      input_map = %{
        "strategy" => "combine_arrays",
        "inputs" => [
          [1, 2, 3],
          [4, 5],
          %{"ignored" => "non-array"}
        ]
      }
      
      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == [1, 2, 3, 4, 5]
    end

    test "last_wins strategy returns last input" do
      input_map = %{
        "strategy" => "last_wins",
        "inputs" => [
          %{"first" => true},
          %{"second" => true},
          %{"third" => true}
        ]
      }
      
      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == %{"third" => true}
    end

    test "defaults to combine_objects strategy" do
      input_map = %{
        "inputs" => [
          %{"a" => 1},
          %{"b" => 2}
        ]
      }
      
      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == %{"a" => 1, "b" => 2}
    end

    test "handles empty inputs list" do
      input_map = %{
        "strategy" => "combine_objects",
        "inputs" => []
      }
      
      assert {:ok, result, "success"} = Data.merge(input_map)
      assert result == %{}
    end

    test "returns error for unknown strategy" do
      input_map = %{
        "strategy" => "unknown_strategy",
        "inputs" => [%{"test" => true}]
      }
      
      assert {:error, error, "error"} = Data.merge(input_map)
      assert error.type == "merge_error"
      assert String.contains?(error.message, "unknown_strategy")
    end
  end
end