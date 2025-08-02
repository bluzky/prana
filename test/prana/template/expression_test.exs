defmodule Prana.Template.ExpressionTest do
  use ExUnit.Case, async: true
  alias Prana.Template.Engine

  describe "simple expression rendering" do
    setup do
      context = %{
        "$input" => %{
          "name" => "Alice",
          "age" => 25,
          "active" => true,
          "inactive" => false,
          "score" => 95.5,
          "nested" => %{
            "field" => "nested_value",
            "deep" => %{"value" => "very_deep"}
          }
        },
        "$variables" => %{
          "app_name" => "MyApp",
          "version" => "1.0.0"
        }
      }

      {:ok, context: context}
    end

    test "renders simple string variable", %{context: context} do
      template = "Hello {{ $input.name }}!"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Hello Alice!"
    end

    test "renders simple number variable", %{context: context} do
      template = "Age: {{ $input.age }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Age: 25"
    end

    test "renders boolean variables", %{context: context} do
      template1 = "Active: {{ $input.active }}"
      assert {:ok, "Active: true"} = Engine.render(template1, context)

      template2 = "Inactive: {{ $input.inactive }}"
      assert {:ok, "Inactive: false"} = Engine.render(template2, context)
    end

    test "renders float variables", %{context: context} do
      template = "Score: {{ $input.score }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Score: 95.5"
    end

    test "renders nested field access", %{context: context} do
      template = "Nested: {{ $input.nested.field }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Nested: nested_value"
    end

    test "renders deeply nested field access", %{context: context} do
      template = "Deep: {{ $input.nested.deep.value }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Deep: very_deep"
    end

    test "renders variables section", %{context: context} do
      template = "App: {{ $variables.app_name }} v{{ $variables.version }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "App: MyApp v1.0.0"
    end

    test "pure expression returns original data type", %{context: context} do
      # Single expression should return the original type, not string
      template = "{{ $input.age }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 25  # Number, not "25"
    end

    test "pure boolean expression returns boolean", %{context: context} do
      template = "{{ $input.active }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # Boolean, not "true"
    end

    test "pure nested expression returns original type", %{context: context} do
      template = "{{ $input.nested.field }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "nested_value"  # String as expected
    end

    test "mixed content returns string", %{context: context} do
      template = "Name: {{ $input.name }}, Age: {{ $input.age }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Name: Alice, Age: 25"
      assert is_binary(result)
    end

    test "handles missing variables gracefully", %{context: context} do
      template = "Missing: {{ $input.missing_field }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Missing: "  # Empty string for missing values
    end

    test "handles missing nested fields gracefully", %{context: context} do
      template = "Missing nested: {{ $input.nested.missing }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Missing nested: "
    end

    test "renders literal text without expressions", %{context: _context} do
      template = "This is just plain text with no expressions"

      assert {:ok, result} = Engine.render(template, %{})
      assert result == "This is just plain text with no expressions"
    end

    test "handles empty template", %{context: _context} do
      template = ""

      assert {:ok, result} = Engine.render(template, %{})
      assert result == ""
    end

    test "handles whitespace in expressions", %{context: context} do
      template = "Hello {{   $input.name   }}!"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Hello Alice!"
    end

    test "handles multiple expressions in one template", %{context: context} do
      template = "{{ $input.name }} is {{ $input.age }} years old and is {{ $input.active }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Alice is 25 years old and is true"
    end
  end

  describe "arithmetic expressions" do
    setup do
      context = %{
        "$input" => %{
          "a" => 10,
          "b" => 5,
          "c" => 2.5
        }
      }

      {:ok, context: context}
    end

    test "renders addition", %{context: context} do
      template = "Result: {{ $input.a + $input.b }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Result: 15"
    end

    test "renders subtraction", %{context: context} do
      template = "Result: {{ $input.a - $input.b }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Result: 5"
    end

    test "renders multiplication", %{context: context} do
      template = "Result: {{ $input.a * $input.b }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Result: 50"
    end

    test "renders division", %{context: context} do
      template = "Result: {{ $input.a / $input.b }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Result: 2.0"
    end

    test "renders complex arithmetic", %{context: context} do
      template = "Result: {{ ($input.a + $input.b) * $input.c }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Result: 37.5"
    end

    test "pure arithmetic expression returns number", %{context: context} do
      template = "{{ $input.a + $input.b }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 15  # Number, not "15"
    end
  end

  describe "nested parentheses with arithmetic operators" do
    setup do
      context = %{
        "$input" => %{
          "a" => 10,
          "b" => 5,
          "c" => 2,
          "d" => 3,
          "items" => ["x", "y", "z"],
          "users" => [%{"name" => "Alice"}, %{"name" => "Bob"}]
        }
      }

      {:ok, context: context}
    end

    test "simple nested parentheses", %{context: context} do
      template = "{{ ($input.a + $input.b) * $input.c }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 30  # (10 + 5) * 2 = 30
    end

    test "multiple levels of nesting", %{context: context} do
      template = "{{ (($input.a + $input.b) * $input.c) + $input.d }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 33  # ((10 + 5) * 2) + 3 = 33
    end

    test "nested parentheses with subtraction", %{context: context} do
      template = "{{ ($input.a - ($input.b + $input.c)) * $input.d }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 9  # (10 - (5 + 2)) * 3 = 9
    end

    test "nested parentheses with division", %{context: context} do
      template = "{{ ($input.a + $input.b) / ($input.c + $input.d) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 3.0  # (10 + 5) / (2 + 3) = 3.0
    end

    test "complex nested expression with mixed operators", %{context: context} do
      template = "{{ (($input.a * $input.b) + ($input.c - $input.d)) / $input.c }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 24.5  # ((10 * 5) + (2 - 3)) / 2 = 49 / 2 = 24.5
    end

    test "nested parentheses with function calls", %{context: context} do
      template = "{{ ($input.items | length()) + ($input.users | length()) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 5  # 3 + 2 = 5
    end

    test "function call result in arithmetic expression", %{context: context} do
      template = "{{ ($input.items | length()) * ($input.a + $input.b) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 45  # 3 * (10 + 5) = 45
    end

    test "nested function calls with arithmetic", %{context: context} do
      template = "{{ (($input.items | length()) + $input.c) * $input.d }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 15  # ((3) + 2) * 3 = 15
    end

    test "deeply nested with multiple operations", %{context: context} do
      template = "{{ ((($input.a + $input.b) * $input.c) - $input.d) / ($input.items | length()) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 9.0  # (((10 + 5) * 2) - 3) / 3 = 27 / 3 = 9.0
    end

    test "nested parentheses in mixed content returns string", %{context: context} do
      template = "Result: {{ ($input.a + $input.b) * $input.c }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Result: 30"
      assert is_binary(result)
    end

    test "pure nested expression preserves number type", %{context: context} do
      template = "{{ (($input.a + $input.b) * $input.c) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 30
      assert is_integer(result)
    end

    test "handles precedence correctly without parentheses", %{context: context} do
      template = "{{ $input.a + $input.b * $input.c }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 20  # 10 + (5 * 2) = 20, multiplication has higher precedence
    end

    test "parentheses override natural precedence", %{context: context} do
      template = "{{ ($input.a + $input.b) * $input.c }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == 30  # (10 + 5) * 2 = 30
    end
  end

  describe "nested parentheses with boolean operators" do
    setup do
      context = %{
        "$input" => %{
          "age" => 25,
          "score" => 85,
          "active" => true,
          "premium" => false,
          "count" => 10,
          "limit" => 5,
          "name" => "Alice",
          "role" => "admin"
        }
      }

      {:ok, context: context}
    end

    test "simple boolean with parentheses", %{context: context} do
      template = "{{ ($input.age > 18) && $input.active }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # (25 > 18) && true = true
    end

    test "nested boolean with AND/OR precedence", %{context: context} do
      template = "{{ $input.active && ($input.age > 18 || $input.premium) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # true && (true || false) = true
    end

    test "complex nested boolean conditions", %{context: context} do
      template = "{{ ($input.age >= 18 && $input.score > 80) || ($input.premium && $input.active) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # (true && true) || (false && true) = true
    end

    test "boolean with arithmetic in parentheses", %{context: context} do
      template = "{{ ($input.count * 2) > ($input.age + $input.limit) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == false  # (10 * 2) > (25 + 5) = 20 > 30 = false
    end

    test "nested boolean with string comparisons", %{context: context} do
      template = "{{ ($input.name == \"Alice\") && ($input.role == \"admin\" || $input.premium) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # (true) && (true || false) = true
    end

    test "deeply nested boolean logic", %{context: context} do
      template = "{{ (($input.age > 18 && $input.active) || $input.premium) && ($input.score >= 80) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # ((true && true) || false) && true = true
    end

    test "boolean precedence without parentheses", %{context: context} do
      # AND has higher precedence than OR
      template = "{{ $input.active || $input.premium && $input.age > 18 }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # true || (false && true) = true
    end

    test "parentheses override boolean precedence", %{context: context} do
      template = "{{ ($input.active || $input.premium) && $input.age > 18 }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # (true || false) && true = true
    end

    test "mixed arithmetic and boolean in nested parentheses", %{context: context} do
      template = "{{ (($input.count + $input.limit) > $input.age) && ($input.score >= 80) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == false  # ((10 + 5) > 25) && (85 >= 80) = false && true = false
    end

    test "comparison operators with parentheses", %{context: context} do
      template = "{{ ($input.age >= 21) || ($input.score > 90 && $input.active) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # (25 >= 21) || (false && true) = true || false = true
    end

    test "negation with nested parentheses", %{context: context} do
      # Using inequality as negation since ! operator may not be implemented
      template = "{{ ($input.premium != true) && ($input.age > 18 && $input.active) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # (false != true) && (true && true) = true && true = true
    end

    test "complex boolean expression with all operators", %{context: context} do
      template = "{{ (($input.age >= 18 && $input.score > 70) || $input.premium) && ($input.active != false) }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true  # ((true && true) || false) && (true != false) = true && true = true
    end

    test "boolean in mixed content returns string", %{context: context} do
      template = "Access: {{ ($input.age >= 18) && $input.active }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Access: true"
      assert is_binary(result)
    end

    test "pure boolean expression preserves boolean type", %{context: context} do
      template = "{{ ($input.age >= 18) && $input.active }}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == true
      assert is_boolean(result)
    end

    test "nested boolean with function calls", %{context: context} do
      # Test boolean logic with function results
      context_with_items = Map.put(context, "$input", Map.put(context["$input"], "items", ["a", "b", "c"]))
      template = "{{ ($input.items | length()) > 2 && $input.active }}"

      assert {:ok, result} = Engine.render(template, context_with_items)
      assert result == true  # (3 > 2) && true = true
    end
  end
end