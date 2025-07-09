defmodule Prana.Template.Filters.NumberFiltersTest do
  use ExUnit.Case, async: false

  alias Prana.Template.Engine

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
      assert {:ok, 123.46} = Engine.render("{{ $input.price | round(2) }}", context)
      
      # Round to 0 decimal places (integer)
      assert {:ok, 123.0} = Engine.render("{{ $input.price | round(0) }}", context)
      
      # Round to 4 decimal places
      assert {:ok, 123.4568} = Engine.render("{{ $input.price | round(4) }}", context)
    end

    test "round filter with different numbers", %{context: context} do
      # Integer parameter
      assert {:ok, 3.14} = Engine.render("{{ $input.number | round(2) }}", context)
      
      # Different integer parameter
      assert {:ok, 3.1416} = Engine.render("{{ $input.number | round(4) }}", context)
    end

    test "format_currency filter with currency code parameter", %{context: context} do
      # Format as USD
      assert {:ok, "$42.00"} = Engine.render("{{ $input.amount | format_currency(\"USD\") }}", context)
      
      # Format as EUR
      assert {:ok, "€42.00"} = Engine.render("{{ $input.amount | format_currency(\"EUR\") }}", context)
      
      # Format as GBP
      assert {:ok, "£42.00"} = Engine.render("{{ $input.amount | format_currency(\"GBP\") }}", context)
      
      # Mixed template with currency formatting
      assert {:ok, "Total: $42.00"} = Engine.render("Total: {{ $input.amount | format_currency(\"USD\") }}", context)
    end

    test "chained number filters", %{context: context} do
      # Chain: round then format currency
      assert {:ok, "$123.46"} = Engine.render("{{ $input.price | round(2) | format_currency(\"USD\") }}", context)
      
      # Mixed template with chained filters
      assert {:ok, "Price: $123.46"} = Engine.render("Price: {{ $input.price | round(2) | format_currency(\"USD\") }}", context)
    end
  end
end