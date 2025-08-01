defmodule Prana.Template.Filters.FilterChainingTest do
  use ExUnit.Case, async: false

  alias Prana.Template.Engine

  describe "filter chaining across types" do
    setup do
      context = %{
        "$input" => %{
          "name" => "john doe",
          "description" => "This is a very long description that should be truncated for display purposes",
          "price" => 123.456789,
          "items" => ["apple", "banana", "cherry", "date"]
        }
      }

      {:ok, context: context}
    end

    test "string to string filter chains", %{context: context} do
      # Chain: uppercase then truncate
      assert {:ok, "JOHN DOE"} = Engine.render("{{ $input.name | upper_case | truncate(10) }}", context)

      # Chain: capitalize then truncate with custom suffix
      assert {:ok, "John doe"} = Engine.render("{{ $input.name | capitalize | truncate(10, \"...\") }}", context)
      assert {:ok, "John doe"} = Engine.render("{{ $input.name | capitalize | truncate(8, \"...\") }}", context)
      assert {:ok, "John..."} = Engine.render("{{ $input.name | capitalize | truncate(7, \"...\") }}", context)
    end

    test "number to string filter chains", %{context: context} do
      # Chain: round then format currency
      assert {:ok, "$123.46"} = Engine.render("{{ $input.price | round(2) | format_currency(\"USD\") }}", context)

      # Chain: round then default (should not use default)
      assert {:ok, 123.46} = Engine.render("{{ $input.price | round(2) | default(\"N/A\") }}", context)
    end

    test "collection to string filter chains", %{context: context} do
      # Chain: join then upper_case
      assert {:ok, "APPLE,BANANA,CHERRY,DATE"} = Engine.render("{{ $input.items | join(\",\") | upper_case }}", context)

      # Chain: first then upper_case
      assert {:ok, "APPLE"} = Engine.render("{{ $input.items | first | upper_case }}", context)

      # Chain: last then capitalize then truncate
      assert {:ok, "Date"} = Engine.render("{{ $input.items | last | capitalize | truncate(10) }}", context)
    end

    test "complex multi-type chains", %{context: context} do
      # Chain: collection -> string -> string
      assert {:ok, "APPLE,BANANA,CHERRY,DATE"} = Engine.render("{{ $input.items | join(\",\") | upper_case }}", context)

      # Chain: number -> string -> string
      assert {:ok, "$123.46"} = Engine.render("{{ $input.price | round(2) | format_currency(\"USD\") }}", context)
    end

    test "chained filters in mixed templates", %{context: context} do
      # Mixed template with string chain
      assert {:ok, "Name: JOHN DOE"} = Engine.render("Name: {{ $input.name | upper_case | truncate(10) }}", context)

      # Mixed template with number chain
      assert {:ok, "Price: $123.46"} =
               Engine.render("Price: {{ $input.price | round(2) | format_currency(\"USD\") }}", context)

      # Mixed template with collection chain
      assert {:ok, "Items: APPLE,BANANA,CHERRY,DATE"} =
               Engine.render("Items: {{ $input.items | join(\",\") | upper_case }}", context)
    end
  end
end
