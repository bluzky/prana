defmodule Prana.Template.Filters.StringFiltersTest do
  use ExUnit.Case, async: false

  alias Prana.Template.Engine

  describe "string filters" do
    setup do
      context = %{
        "$input" => %{
          "name" => "john doe",
          "description" => "This is a very long description that should be truncated for display purposes",
          "text" => "hello world"
        }
      }
      
      {:ok, context: context}
    end

    test "upper_case filter", %{context: context} do
      # Pure expression
      assert {:ok, "JOHN DOE"} = Engine.render("{{ $input.name | upper_case }}", context)
      
      # Mixed template
      assert {:ok, "Hello JOHN DOE!"} = Engine.render("Hello {{ $input.name | upper_case }}!", context)
    end

    test "lower_case filter", %{context: context} do
      # Pure expression
      assert {:ok, "john doe"} = Engine.render("{{ $input.name | lower_case }}", context)
      
      # Mixed template
      assert {:ok, "Hello john doe!"} = Engine.render("Hello {{ $input.name | lower_case }}!", context)
    end

    test "capitalize filter", %{context: context} do
      # Pure expression
      assert {:ok, "John doe"} = Engine.render("{{ $input.name | capitalize }}", context)
      
      # Mixed template
      assert {:ok, "Hello John doe!"} = Engine.render("Hello {{ $input.name | capitalize }}!", context)
    end

    test "truncate filter with length parameter", %{context: context} do
      # Pure expression with truncate and length parameter
      assert {:ok, "This is a ve..."} = Engine.render("{{ $input.description | truncate(15) }}", context)
      
      # Mixed template with truncate
      assert {:ok, "Description: This is a ve..."} = Engine.render("Description: {{ $input.description | truncate(15) }}", context)
    end

    test "truncate filter with length and custom suffix", %{context: context} do
      # Truncate with custom suffix (15 - 2 = 13 chars + "--")
      assert {:ok, "This is a ver--"} = Engine.render("{{ $input.description | truncate(15, \"--\") }}", context)
      
      # Truncate with different suffix (10 - 3 = 7 chars + "***")
      assert {:ok, "This is***"} = Engine.render("{{ $input.description | truncate(10, \"***\") }}", context)
    end

    test "truncate filter with parameter types", %{context: context} do
      # String parameter with double quotes (10 - 3 = 7 chars + "...")
      assert {:ok, "hello w..."} = Engine.render("{{ $input.text | truncate(10, \"...\") }}", context)
      
      # String parameter with single quotes (10 - 3 = 7 chars + "---")
      assert {:ok, "hello w---"} = Engine.render("{{ $input.text | truncate(10, '---') }}", context)
      
      # Multiple parameters in correct order (8 - 3 = 5 chars + ">>>")
      assert {:ok, "hello>>>"} = Engine.render("{{ $input.text | truncate(8, \">>>\") }}", context)
    end

    test "default filter with fallback value", %{context: context} do
      # Missing field with default
      assert {:ok, "Unknown"} = Engine.render("{{ $input.missing_name | default(\"Unknown\") }}", context)
      
      # Existing field (default not used)
      assert {:ok, "john doe"} = Engine.render("{{ $input.name | default(\"Unknown\") }}", context)
      
      # Mixed template with default
      assert {:ok, "Name: Unknown"} = Engine.render("Name: {{ $input.missing_name | default(\"Unknown\") }}", context)
    end

    test "chained string filters", %{context: context} do
      # Chain: uppercase then truncate
      assert {:ok, "JOHN DOE"} = Engine.render("{{ $input.name | upper_case | truncate(10) }}", context)
      
      # Chain: capitalize then truncate
      assert {:ok, "John doe"} = Engine.render("{{ $input.name | capitalize | truncate(10) }}", context)
    end
  end
end