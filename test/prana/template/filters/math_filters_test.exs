defmodule Prana.Template.Filters.MathFiltersTest do
  use ExUnit.Case, async: false

  alias Prana.Template

  describe "math filters" do
    setup do
      context = %{
        "$input" => %{
          "positive" => 42.5,
          "negative" => -17.3,
          "integer" => 10,
          "zero" => 0,
          "float" => 3.14159,
          "string_number" => "25.75",
          "large" => 100.0,
          "small" => 5.0
        }
      }

      {:ok, context: context}
    end

    test "abs filter with positive numbers", %{context: context} do
      # Pure expression with positive number
      assert {:ok, 42.5} = Template.render("{{ $input.positive | abs }}", context)
      assert {:ok, 10} = Template.render("{{ $input.integer | abs }}", context)

      # Mixed template
      assert {:ok, "Value: 42.5"} = Template.render("Value: {{ $input.positive | abs }}", context)
    end

    test "abs filter with negative numbers", %{context: context} do
      # Pure expression with negative number
      assert {:ok, 17.3} = Template.render("{{ $input.negative | abs }}", context)

      # Mixed template
      assert {:ok, "Absolute: 17.3"} = Template.render("Absolute: {{ $input.negative | abs }}", context)
    end

    test "abs filter with zero", %{context: context} do
      assert {:ok, 0} = Template.render("{{ $input.zero | abs }}", context)
    end

    test "abs filter with string numbers", %{context: context} do
      assert {:ok, 25.75} = Template.render("{{ $input.string_number | abs }}", context)

      # Test with negative string
      context_negative_string = Map.put(context, "$input", Map.put(context["$input"], "negative_string", "-15.5"))
      assert {:ok, 15.5} = Template.render("{{ $input.negative_string | abs }}", context_negative_string)
    end

    test "ceil filter", %{context: context} do
      # Positive numbers
      assert {:ok, 43} = Template.render("{{ $input.positive | ceil }}", context)
      assert {:ok, 4} = Template.render("{{ $input.float | ceil }}", context)

      # Negative numbers
      assert {:ok, -17} = Template.render("{{ $input.negative | ceil }}", context)

      # Whole numbers
      assert {:ok, 10} = Template.render("{{ $input.integer | ceil }}", context)

      # Zero
      assert {:ok, 0} = Template.render("{{ $input.zero | ceil }}", context)
    end

    test "floor filter", %{context: context} do
      # Positive numbers
      assert {:ok, 42} = Template.render("{{ $input.positive | floor }}", context)
      assert {:ok, 3} = Template.render("{{ $input.float | floor }}", context)

      # Negative numbers
      assert {:ok, -18} = Template.render("{{ $input.negative | floor }}", context)

      # Whole numbers
      assert {:ok, 10} = Template.render("{{ $input.integer | floor }}", context)

      # Zero
      assert {:ok, 0} = Template.render("{{ $input.zero | floor }}", context)
    end

    test "max filter", %{context: context} do
      # Compare two numbers
      assert {:ok, 100.0} = Template.render("{{ $input.large | max(50) }}", context)
      assert {:ok, 50} = Template.render("{{ $input.small | max(50) }}", context)

      # With negative numbers
      assert {:ok, 10} = Template.render("{{ $input.integer | max(-5) }}", context)
      assert {:ok, -5} = Template.render("{{ $input.negative | max(-5) }}", context)

      # Mixed template
      assert {:ok, "Max: 100.0"} = Template.render("Max: {{ $input.large | max(50) }}", context)
    end

    test "min filter", %{context: context} do
      # Compare two numbers
      assert {:ok, 50} = Template.render("{{ $input.large | min(50) }}", context)
      assert {:ok, 5.0} = Template.render("{{ $input.small | min(50) }}", context)

      # With negative numbers
      assert {:ok, -5} = Template.render("{{ $input.integer | min(-5) }}", context)
      assert {:ok, -17.3} = Template.render("{{ $input.negative | min(-5) }}", context)

      # Mixed template
      assert {:ok, "Min: 5.0"} = Template.render("Min: {{ $input.small | min(50) }}", context)
    end

    test "power filter", %{context: context} do
      # Integer powers
      assert {:ok, 100.0} = Template.render("{{ $input.integer | power(2) }}", context)
      assert {:ok, 1000.0} = Template.render("{{ $input.integer | power(3) }}", context)

      # Fractional powers
      assert {:ok, result} = Template.render("{{ $input.large | power(0.5) }}", context)
      assert_in_delta result, 10.0, 0.001

      # Power of zero
      assert {:ok, 1.0} = Template.render("{{ $input.small | power(0) }}", context)

      # Mixed template
      assert {:ok, "Result: 100.0"} = Template.render("Result: {{ $input.integer | power(2) }}", context)
    end

    test "sqrt filter", %{context: context} do
      # Perfect squares
      assert {:ok, result} = Template.render("{{ $input.large | sqrt }}", context)
      assert_in_delta result, 10.0, 0.001

      # Non-perfect squares
      assert {:ok, result} = Template.render("{{ $input.small | sqrt }}", context)
      assert_in_delta result, 2.236, 0.001

      # Zero
      assert {:ok, +0.0} = Template.render("{{ $input.zero | sqrt }}", context)

      # Mixed template
      assert {:ok, result} = Template.render("Square root: {{ $input.large | sqrt }}", context)
      assert String.contains?(result, "10.0")
    end

    test "sqrt filter with negative numbers", %{context: context} do
      # Should return error for negative numbers
      assert {:error, result} = Template.render("{{ $input.negative | sqrt }}", context)
      assert String.contains?(result, "sqrt filter cannot calculate square root of negative number")
    end

    test "mod filter", %{context: context} do
      # Basic mod operations
      assert {:ok, 0} = Template.render("{{ $input.integer | mod(5) }}", context)
      assert {:ok, 2} = Template.render("{{ 17 | mod(5) }}", context)

      # With larger numbers
      assert {:ok, 0} = Template.render("{{ $input.large | mod(10) }}", context)

      # Mixed template
      assert {:ok, "Remainder: 0"} = Template.render("Remainder: {{ $input.integer | mod(5) }}", context)
    end

    test "mod filter with zero divisor", %{context: context} do
      # Should return error for division by zero
      assert {:error, result} = Template.render("{{ $input.integer | mod(0) }}", context)
      assert String.contains?(result, "mod filter cannot divide by zero")
    end

    test "clamp filter", %{context: context} do
      # Value within range
      assert {:ok, 10} = Template.render("{{ $input.integer | clamp(0, 20) }}", context)

      # Value below minimum
      assert {:ok, 0} = Template.render("{{ $input.negative | clamp(0, 20) }}", context)

      # Value above maximum
      assert {:ok, 20} = Template.render("{{ $input.large | clamp(0, 20) }}", context)

      # Mixed template
      assert {:ok, "Clamped: 10"} = Template.render("Clamped: {{ $input.integer | clamp(0, 20) }}", context)
    end

    test "clamp filter with invalid range", %{context: context} do
      # Should return error when min_val > max_val
      assert {:error, result} = Template.render("{{ $input.integer | clamp(20, 10) }}", context)
      assert String.contains?(result, "clamp filter requires min_val (20) to be <= max_val (10)")
    end

    test "chained math filters", %{context: context} do
      # Chain: abs then ceil
      assert {:ok, 18} = Template.render("{{ $input.negative | abs | ceil }}", context)

      # Chain: floor then power
      assert {:ok, 9.0} = Template.render("{{ $input.float | floor | power(2) }}", context)

      # Chain: sqrt then round (from number filters)
      assert {:ok, 10.0} = Template.render("{{ $input.large | sqrt | round(1) }}", context)
    end

    test "math filters with literal values", %{context: context} do
      # Test with numeric literals
      assert {:ok, 25} = Template.render("{{ 25 | abs }}", context)
      assert {:ok, 4} = Template.render("{{ 3.7 | ceil }}", context)
      assert {:ok, 3} = Template.render("{{ 3.7 | floor }}", context)
      assert {:ok, 8.0} = Template.render("{{ 2 | power(3) }}", context)
    end

    test "type preservation in pure expressions", %{context: context} do
      # Pure math expressions should return numbers
      assert {:ok, result} = Template.render("{{ $input.positive | abs }}", context)
      assert result == 42.5
      assert is_float(result)

      assert {:ok, result} = Template.render("{{ $input.integer | abs }}", context)
      assert result == 10
      assert is_integer(result)
    end

    test "mixed content returns string", %{context: context} do
      # Mixed content should always return string
      assert {:ok, result} = Template.render("Value: {{ $input.positive | abs }}", context)
      assert result == "Value: 42.5"
      assert is_binary(result)
    end

    test "error handling for invalid inputs", %{context: context} do
      # Test with non-numeric strings
      context_invalid = Map.put(context, "$input", Map.put(context["$input"], "invalid", "not_a_number"))

      assert {:error, result} = Template.render("{{ $input.invalid | abs }}", context_invalid)
      assert String.contains?(result, "abs filter requires a numeric value")
    end

    test "complex mathematical expressions", %{context: context} do
      # Combine multiple math operations
      template = "{{ ($input.integer | power(2) | sqrt) | round(2) }}"
      assert {:ok, 10.0} = Template.render(template, context)

      # Nested operations
      template2 = "{{ ($input.large | sqrt | floor) | power(2) }}"
      assert {:ok, 100.0} = Template.render(template2, context)
    end
  end
end
