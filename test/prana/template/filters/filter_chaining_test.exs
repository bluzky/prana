defmodule Prana.Template.Filters.FilterChainingTest do
  use ExUnit.Case, async: false

  alias Prana.Template

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
      assert {:ok, "JOHN DOE"} = Template.render("{{ $input.name | upper_case | truncate(10) }}", context)

      # Chain: capitalize then truncate with custom suffix
      assert {:ok, "John doe"} = Template.render("{{ $input.name | capitalize | truncate(10, \"...\") }}", context)
      assert {:ok, "John doe"} = Template.render("{{ $input.name | capitalize | truncate(8, \"...\") }}", context)
      assert {:ok, "John..."} = Template.render("{{ $input.name | capitalize | truncate(7, \"...\") }}", context)
    end

    test "number to string filter chains", %{context: context} do
      # Chain: round then format currency
      assert {:ok, "$123.46"} = Template.render("{{ $input.price | round(2) | format_currency(\"USD\") }}", context)

      # Chain: round then default (should not use default)
      assert {:ok, 123.46} = Template.render("{{ $input.price | round(2) | default(\"N/A\") }}", context)
    end

    test "collection to string filter chains", %{context: context} do
      # Chain: join then upper_case
      assert {:ok, "APPLE,BANANA,CHERRY,DATE"} = Template.render("{{ $input.items | join(\",\") | upper_case }}", context)

      # Chain: first then upper_case
      assert {:ok, "APPLE"} = Template.render("{{ $input.items | first | upper_case }}", context)

      # Chain: last then capitalize then truncate
      assert {:ok, "Date"} = Template.render("{{ $input.items | last | capitalize | truncate(10) }}", context)
    end

    test "complex multi-type chains", %{context: context} do
      # Chain: collection -> string -> string
      assert {:ok, "APPLE,BANANA,CHERRY,DATE"} = Template.render("{{ $input.items | join(\",\") | upper_case }}", context)

      # Chain: number -> string -> string
      assert {:ok, "$123.46"} = Template.render("{{ $input.price | round(2) | format_currency(\"USD\") }}", context)
    end

    test "chained filters in mixed templates", %{context: context} do
      # Mixed template with string chain
      assert {:ok, "Name: JOHN DOE"} = Template.render("Name: {{ $input.name | upper_case | truncate(10) }}", context)

      # Mixed template with number chain
      assert {:ok, "Price: $123.46"} =
               Template.render("Price: {{ $input.price | round(2) | format_currency(\"USD\") }}", context)

      # Mixed template with collection chain
      assert {:ok, "Items: APPLE,BANANA,CHERRY,DATE"} =
               Template.render("Items: {{ $input.items | join(\",\") | upper_case }}", context)
    end

    test "complex filter chain with truncate and case conversion", %{context: context} do
      # Complex chain: truncate then upper_case
      template = "{{ $input.description | truncate(20) | upper_case }}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "THIS IS A VERY LO..."
      assert String.length(result) == 20
    end

    test "filter chain with variable arguments and defaults", %{context: context} do
      # Chain: round with precision then format_currency with default USD
      template = "{{ $input.price | round(1) | format_currency }}"

      assert {:ok, result} = Template.render(template, context)
      # 123.456789 rounded to 1 decimal = 123.5, formatted as currency = $123.50
      assert result == "$123.50"
    end

    test "type preservation in pure chained expressions", %{context: context} do
      # Pure expression with collection -> number should return number
      template = "{{ $input.items | length }}"

      assert {:ok, result} = Template.render(template, context)
      assert result == 4
      assert is_integer(result)
    end

    test "mixed content with chained filters returns string", %{context: context} do
      # Mixed content should always return string regardless of filter chain
      template = "Total items: {{ $input.items | length }} found"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Total items: 4 found"
      assert is_binary(result)
    end

    test "long filter chains across multiple types", %{context: context} do
      # Very long chain: collection -> string -> string -> string
      template = "{{ $input.items | join(\", \") | upper_case | truncate(15) }}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "APPLE, BANAN..."
      assert String.length(result) == 15
    end

    test "filter chains with default arguments", %{context: context} do
      # Test chains using filters with default arguments
      template1 = "{{ $input.items | join | upper_case }}"
      assert {:ok, "APPLE, BANANA, CHERRY, DATE"} = Template.render(template1, context)

      template2 = "{{ $input.price | round | format_currency }}"
      assert {:ok, "$123.00"} = Template.render(template2, context)
    end
  end
end
