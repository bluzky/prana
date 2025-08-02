defmodule Prana.Template.Filters.StringFiltersTest do
  use ExUnit.Case, async: false

  alias Prana.Template

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
      assert {:ok, "JOHN DOE"} = Template.render("{{ $input.name | upper_case }}", context)

      # Mixed template
      assert {:ok, "Hello JOHN DOE!"} = Template.render("Hello {{ $input.name | upper_case }}!", context)
    end

    test "lower_case filter", %{context: context} do
      # Pure expression
      assert {:ok, "john doe"} = Template.render("{{ $input.name | lower_case }}", context)

      # Mixed template
      assert {:ok, "Hello john doe!"} = Template.render("Hello {{ $input.name | lower_case }}!", context)
    end

    test "capitalize filter", %{context: context} do
      # Pure expression
      assert {:ok, "John doe"} = Template.render("{{ $input.name | capitalize }}", context)

      # Mixed template
      assert {:ok, "Hello John doe!"} = Template.render("Hello {{ $input.name | capitalize }}!", context)
    end

    test "truncate filter with length parameter", %{context: context} do
      # Pure expression with truncate and length parameter
      assert {:ok, "This is a ve..."} = Template.render("{{ $input.description | truncate(15) }}", context)

      # Mixed template with truncate
      assert {:ok, "Description: This is a ve..."} =
               Template.render("Description: {{ $input.description | truncate(15) }}", context)
    end

    test "truncate filter with length and custom suffix", %{context: context} do
      # Truncate with custom suffix (15 - 2 = 13 chars + "--")
      assert {:ok, "This is a ver--"} = Template.render("{{ $input.description | truncate(15, \"--\") }}", context)

      # Truncate with different suffix (10 - 3 = 7 chars + "***")
      assert {:ok, "This is***"} = Template.render("{{ $input.description | truncate(10, \"***\") }}", context)
    end

    test "truncate filter with parameter types", %{context: context} do
      # String parameter with double quotes (10 - 3 = 7 chars + "...")
      assert {:ok, "hello w..."} = Template.render("{{ $input.text | truncate(10, \"...\") }}", context)

      # String parameter with single quotes (10 - 3 = 7 chars + "---")
      assert {:ok, "hello w---"} = Template.render("{{ $input.text | truncate(10, '---') }}", context)

      # Multiple parameters in correct order (8 - 3 = 5 chars + ">>>")
      assert {:ok, "hello>>>"} = Template.render("{{ $input.text | truncate(8, \">>>\") }}", context)
    end

    test "default filter with fallback value", %{context: context} do
      # Missing field with default
      assert {:ok, "Unknown"} = Template.render("{{ $input.missing_name | default(\"Unknown\") }}", context)

      # Existing field (default not used)
      assert {:ok, "john doe"} = Template.render("{{ $input.name | default(\"Unknown\") }}", context)

      # Mixed template with default
      assert {:ok, "Name: Unknown"} = Template.render("Name: {{ $input.missing_name | default(\"Unknown\") }}", context)
    end

    test "chained string filters", %{context: context} do
      # Chain: uppercase then truncate
      assert {:ok, "JOHN DOE"} = Template.render("{{ $input.name | upper_case | truncate(10) }}", context)

      # Chain: capitalize then truncate
      assert {:ok, "John doe"} = Template.render("{{ $input.name | capitalize | truncate(10) }}", context)
    end

    test "string filters with literal values", %{context: context} do
      # Test with string literals instead of variables
      assert {:ok, "hello world"} = Template.render("{{ \"HELLO WORLD\" | lower_case }}", context)
      assert {:ok, "HELLO WORLD"} = Template.render("{{ \"hello world\" | upper_case }}", context)
      assert {:ok, "Hello world"} = Template.render("{{ \"hello world\" | capitalize }}", context)
    end

    test "type preservation in pure expressions", %{context: context} do
      # Pure string expressions should return strings
      assert {:ok, result} = Template.render("{{ $input.name | upper_case }}", context)
      assert result == "JOHN DOE"
      assert is_binary(result)
    end

    test "mixed content returns string", %{context: context} do
      # Mixed content should always return string
      assert {:ok, result} = Template.render("Name: {{ $input.name | upper_case }}", context)
      assert result == "Name: JOHN DOE"
      assert is_binary(result)
    end

    test "edge cases with empty and nil values", %{context: context} do
      # Empty string handling (empty string is not nil, so default doesn't apply)
      context_with_empty = Map.put(context, "$input", Map.put(context["$input"], "empty", ""))
      assert {:ok, ""} = Template.render("{{ $input.empty | upper_case }}", context_with_empty)
      assert {:ok, ""} = Template.render("{{ $input.empty | default(\"fallback\") }}", context_with_empty)

      # Nil value handling
      context_with_nil = Map.put(context, "$input", Map.put(context["$input"], "nil_value", nil))
      assert {:ok, "fallback"} = Template.render("{{ $input.nil_value | default(\"fallback\") }}", context_with_nil)
    end
  end
end
