defmodule Prana.Template.Filters.CollectionFiltersTest do
  use ExUnit.Case, async: false

  alias Prana.Template.Engine

  describe "collection filters" do
    setup do
      context = %{
        "$input" => %{
          "items" => ["apple", "banana", "cherry", "date"],
          "simple_items" => ["a", "b", "c"]
        }
      }

      {:ok, context: context}
    end

    test "length filter", %{context: context} do
      # Pure expression
      assert {:ok, 4} = Engine.render("{{ $input.items | length }}", context)

      # Mixed template
      assert {:ok, "Count: 4"} = Engine.render("Count: {{ $input.items | length }}", context)
    end

    test "first filter", %{context: context} do
      # Pure expression
      assert {:ok, "apple"} = Engine.render("{{ $input.items | first }}", context)

      # Mixed template
      assert {:ok, "First: apple"} = Engine.render("First: {{ $input.items | first }}", context)
    end

    test "last filter", %{context: context} do
      # Pure expression
      assert {:ok, "date"} = Engine.render("{{ $input.items | last }}", context)

      # Mixed template
      assert {:ok, "Last: date"} = Engine.render("Last: {{ $input.items | last }}", context)
    end

    test "join filter with separator parameter", %{context: context} do
      # Join with comma
      assert {:ok, "apple,banana,cherry,date"} = Engine.render("{{ $input.items | join(\",\") }}", context)

      # Join with space
      assert {:ok, "apple banana cherry date"} = Engine.render("{{ $input.items | join(\" \") }}", context)

      # Join with pipe
      assert {:ok, "apple|banana|cherry|date"} = Engine.render("{{ $input.items | join(\"|\") }}", context)

      # Mixed template with join
      assert {:ok, "Items: apple, banana, cherry, date"} =
               Engine.render("Items: {{ $input.items | join(\", \") }}", context)
    end

    test "chained collection filters", %{context: context} do
      # Chain: join then upper_case
      assert {:ok, "APPLE,BANANA,CHERRY,DATE"} = Engine.render("{{ $input.items | join(\",\") | upper_case }}", context)

      # Chain: first then upper_case
      assert {:ok, "APPLE"} = Engine.render("{{ $input.items | first | upper_case }}", context)

      # Chain: last then capitalize
      assert {:ok, "Date"} = Engine.render("{{ $input.items | last | capitalize }}", context)
    end

    test "collection filters with simple items", %{context: context} do
      # Test with smaller collection
      assert {:ok, 3} = Engine.render("{{ $input.simple_items | length }}", context)
      assert {:ok, "a"} = Engine.render("{{ $input.simple_items | first }}", context)
      assert {:ok, "c"} = Engine.render("{{ $input.simple_items | last }}", context)
      assert {:ok, "a-b-c"} = Engine.render("{{ $input.simple_items | join(\"-\") }}", context)
    end

    test "join filter with default separator", %{context: context} do
      # Join with no arguments defaults to ", " separator
      assert {:ok, "apple, banana, cherry, date"} = Engine.render("{{ $input.items | join }}", context)
      assert {:ok, "a, b, c"} = Engine.render("{{ $input.simple_items | join }}", context)
      
      # Mixed template with default join
      assert {:ok, "Items: apple, banana, cherry, date"} = Engine.render("Items: {{ $input.items | join }}", context)
    end

    test "empty collection handling", %{context: context} do
      # Add empty collection to context
      context_with_empty = Map.put(context, "$input", Map.put(context["$input"], "empty_list", []))
      
      # Empty collections should handle gracefully
      assert {:ok, 0} = Engine.render("{{ $input.empty_list | length }}", context_with_empty)
      assert {:ok, nil} = Engine.render("{{ $input.empty_list | first }}", context_with_empty)
      assert {:ok, nil} = Engine.render("{{ $input.empty_list | last }}", context_with_empty)
      assert {:ok, ""} = Engine.render("{{ $input.empty_list | join }}", context_with_empty)
    end

    test "type preservation in pure expressions", %{context: context} do
      # Pure collection expressions should return original types
      assert {:ok, result} = Engine.render("{{ $input.items | length }}", context)
      assert result == 4
      assert is_integer(result)
      
      assert {:ok, result} = Engine.render("{{ $input.items | first }}", context)
      assert result == "apple"
      assert is_binary(result)
    end

    test "mixed content returns string", %{context: context} do
      # Mixed content should always return string
      assert {:ok, result} = Engine.render("Count: {{ $input.items | length }}", context)
      assert result == "Count: 4"
      assert is_binary(result)
    end

    test "collection filters with different data types", %{context: context} do
      # Add different types to context
      context_with_types = Map.put(context, "$input", Map.merge(context["$input"], %{
        "numbers" => [1, 2, 3, 4, 5],
        "mixed" => ["text", 42, true]
      }))
      
      # Test with numbers
      assert {:ok, 5} = Engine.render("{{ $input.numbers | length }}", context_with_types)
      assert {:ok, 1} = Engine.render("{{ $input.numbers | first }}", context_with_types)
      assert {:ok, 5} = Engine.render("{{ $input.numbers | last }}", context_with_types)
      assert {:ok, "1, 2, 3, 4, 5"} = Engine.render("{{ $input.numbers | join }}", context_with_types)
      
      # Test with mixed types
      assert {:ok, 3} = Engine.render("{{ $input.mixed | length }}", context_with_types)
      assert {:ok, "text, 42, true"} = Engine.render("{{ $input.mixed | join }}", context_with_types)
    end
  end
end
