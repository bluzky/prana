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
  end
end
