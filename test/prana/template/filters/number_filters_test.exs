defmodule Prana.Template.Filters.NumberFiltersTest do
  use ExUnit.Case, async: false

  alias Prana.Template

  describe "number filters" do
    setup do
      context = %{
        "$input" => %{
          "price" => 123.456789,
          "amount" => 42.0,
          "number" => 3.14159
        }
      }

      {:ok, context: context}
    end

    test "round filter with decimal places parameter", %{context: context} do
      # Round to 2 decimal places
      assert {:ok, 123.46} = Template.render("{{ $input.price | round(2) }}", context)

      # Round to 0 decimal places (integer)
      assert {:ok, 123.0} = Template.render("{{ $input.price | round(0) }}", context)

      # Round to 4 decimal places
      assert {:ok, 123.4568} = Template.render("{{ $input.price | round(4) }}", context)
    end

    test "round filter with different numbers", %{context: context} do
      # Integer parameter
      assert {:ok, 3.14} = Template.render("{{ $input.number | round(2) }}", context)

      # Different integer parameter
      assert {:ok, 3.1416} = Template.render("{{ $input.number | round(4) }}", context)
    end

    test "format_currency filter with currency code parameter", %{context: context} do
      # Format as USD
      assert {:ok, "$42.00"} = Template.render("{{ $input.amount | format_currency(\"USD\") }}", context)

      # Format as EUR
      assert {:ok, "€42.00"} = Template.render("{{ $input.amount | format_currency(\"EUR\") }}", context)

      # Format as GBP
      assert {:ok, "£42.00"} = Template.render("{{ $input.amount | format_currency(\"GBP\") }}", context)

      # Mixed template with currency formatting
      assert {:ok, "Total: $42.00"} = Template.render("Total: {{ $input.amount | format_currency(\"USD\") }}", context)
    end

    test "chained number filters", %{context: context} do
      # Chain: round then format currency
      assert {:ok, "$123.46"} = Template.render("{{ $input.price | round(2) | format_currency(\"USD\") }}", context)

      # Mixed template with chained filters
      assert {:ok, "Price: $123.46"} =
               Template.render("Price: {{ $input.price | round(2) | format_currency(\"USD\") }}", context)
    end

    test "round filter with default precision", %{context: context} do
      # Round with no arguments defaults to integer rounding
      assert {:ok, 123} = Template.render("{{ $input.price | round }}", context)
      assert {:ok, 42} = Template.render("{{ $input.amount | round }}", context)
      assert {:ok, 3} = Template.render("{{ $input.number | round }}", context)
    end

    test "format_currency filter with default currency", %{context: context} do
      # Format currency with no arguments defaults to USD
      assert {:ok, "$42.00"} = Template.render("{{ $input.amount | format_currency }}", context)
      assert {:ok, "$123.46"} = Template.render("{{ $input.price | format_currency }}", context)
      
      # Mixed template with default currency
      assert {:ok, "Total: $42.00"} = Template.render("Total: {{ $input.amount | format_currency }}", context)
    end

    test "type preservation in pure expressions", %{context: context} do
      # Pure number expressions should return numbers
      assert {:ok, result} = Template.render("{{ $input.price | round(2) }}", context)
      assert result == 123.46
      assert is_float(result)
      
      # Pure rounded integer should return integer (due to our implementation)
      assert {:ok, result} = Template.render("{{ $input.amount | round }}", context)
      assert result == 42
      assert is_integer(result)
    end

    test "mixed content returns string", %{context: context} do
      # Mixed content should always return string
      assert {:ok, result} = Template.render("Price: {{ $input.price | round(2) }}", context)
      assert result == "Price: 123.46"
      assert is_binary(result)
    end

    test "number filters with string input", %{context: context} do
      # String numbers should be parsed and processed
      context_with_string = Map.put(context, "$input", Map.put(context["$input"], "string_number", "99.99"))
      assert {:ok, 100} = Template.render("{{ $input.string_number | round }}", context_with_string)
      assert {:ok, "$99.99"} = Template.render("{{ $input.string_number | format_currency }}", context_with_string)
    end
  end
end
