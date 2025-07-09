defmodule Prana.Template.Filters.FilterErrorHandlingTest do
  use ExUnit.Case, async: false

  alias Prana.Template.Engine

  describe "filter error handling" do
    setup do
      context = %{
        "$input" => %{
          "name" => "john doe",
          "items" => ["apple", "banana", "cherry"],
          "price" => 99.99
        }
      }
      
      {:ok, context: context}
    end

    test "invalid filter name returns original expression", %{context: context} do
      # Invalid filter name should return original expression
      assert {:ok, "{{ $input.name | invalid_filter }}"} = Engine.render("{{ $input.name | invalid_filter }}", context)
      
      # Mixed template with invalid filter
      assert {:ok, "Name: {{ $input.name | invalid_filter }}"} = Engine.render("Name: {{ $input.name | invalid_filter }}", context)
    end

    test "filter with wrong parameter types", %{context: context} do
      # These should still work or fail gracefully
      # Note: Current implementation is quite permissive, but these tests document expected behavior
      
      # String filter on number (should convert to string first)
      assert {:ok, "99.99"} = Engine.render("{{ $input.price | upper_case }}", context)
    end

    test "chained filters with one invalid", %{context: context} do
      # First filter valid, second invalid - should return original expression
      assert {:ok, "{{ $input.name | upper_case | invalid_filter }}"} = Engine.render("{{ $input.name | upper_case | invalid_filter }}", context)
      
      # First filter invalid - should return original expression
      assert {:ok, "{{ $input.name | invalid_filter | upper_case }}"} = Engine.render("{{ $input.name | invalid_filter | upper_case }}", context)
    end

    test "missing field with filters", %{context: context} do
      # Missing field should return empty string when filtered
      assert {:ok, ""} = Engine.render("{{ $input.missing_field | upper_case }}", context)
      
      # Mixed template with missing field and filter
      assert {:ok, "Value: "} = Engine.render("Value: {{ $input.missing_field | upper_case }}", context)
    end

    test "filter parameter parsing errors", %{context: context} do
      # Malformed filter parameters should return original expression
      assert {:ok, "{{ $input.name | truncate( }}"} = Engine.render("{{ $input.name | truncate( }}", context)
      
      # Unclosed quotes in filter parameters
      assert {:ok, "{{ $input.name | truncate(10, \"unclosed }}"} = Engine.render("{{ $input.name | truncate(10, \"unclosed }}", context)
    end
  end
end