defmodule Prana.Template.FunctionTest do
  use ExUnit.Case, async: true

  alias Prana.Template

  describe "function calls" do
    setup do
      context = %{
        "$input" => %{
          "text" => "hello world",
          "price" => 42.50,
          "items" => ["a", "b", "c"],
          "count" => 5
        }
      }

      {:ok, context: context}
    end

    test "function with no arguments", %{context: context} do
      # Some functions might not need arguments - this is a conceptual test
      # The actual implementation depends on what no-arg functions are available
      template = "{{ $input.text | upper_case() }}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "HELLO WORLD"
    end

    test "function with single argument", %{context: context} do
      template = "{{ $input.price | round(1) }}"

      assert {:ok, result} = Template.render(template, context)
      assert result == 42.5
    end

    test "function with multiple arguments", %{context: context} do
      template = "{{ $input.text | truncate(8, \"...\") }}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "hello..."
    end

    test "function with variable arguments", %{context: context} do
      # Using literal arguments since variable arguments are not yet supported
      context_with_vars = Map.put(context, "precision", 2)
      template = "{{ $input.price | round(precision) }}"
      assert {:ok, result} = Template.render(template, context_with_vars)
      assert result == 42.5
    end

    test "chained function calls", %{context: context} do
      template = "{{ $input.text | upper_case() | truncate(8) }}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "HELLO..."
    end

    test "nested function calls in expressions", %{context: context} do
      # This tests function calls within arithmetic or logical expressions
      template = "{{ ($input.items | length()) + $input.count }}"

      assert {:ok, result} = Template.render(template, context)
      # 3 + 5
      assert result == 8
    end

    test "function calls with literal arguments", %{context: context} do
      template = "{{ $input.price | format_currency(\"USD\") }}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "$42.50"
    end

    test "function calls with mixed literal and variable arguments", %{context: context} do
      # Mix of literal strings, numbers, and variables as function arguments
      context_with_currency = Map.put(context, "currency", "EUR")
      template = "{{ $input.price | format_currency(currency) }}"

      assert {:ok, result} = Template.render(template, context_with_currency)
      assert result == "€42.50"
    end

    test "function return types preservation", %{context: context} do
      # Pure expression with function should preserve return type
      template = "{{ $input.items | length() }}"

      assert {:ok, result} = Template.render(template, context)
      # Number, not "3"
      assert result == 3
      assert is_integer(result)
    end

    test "function in mixed content", %{context: context} do
      template = "Total items: {{ $input.items | length() }}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Total items: 3"
      assert is_binary(result)
    end
  end

  describe "function error handling" do
    setup do
      context = %{
        "$input" => %{
          "text" => "hello",
          "number" => 42
        }
      }

      {:ok, context: context}
    end

    test "handles unknown function gracefully", %{context: context} do
      template = "{{ $input.text | unknown_function() }}"

      assert {:error, message} = Template.render(template, context)
      assert message =~ "Unknown filter: unknown_function"
    end

    test "handles function with wrong argument count", %{context: context} do
      template = "{{ $input.text | upper_case(\"extra_arg\") }}"

      assert {:error, message} = Template.render(template, context)
      assert message =~ "takes no arguments" or message =~ "Filter error"
    end

    test "handles function with invalid argument types", %{context: context} do
      template = "{{ $input.number | truncate(\"not_a_number\") }}"

      assert {:error, message} = Template.render(template, context)
      assert message =~ "Filter error" or message =~ "truncate"
    end

    test "handles function with missing variable arguments", %{context: context} do
      template = "{{ $input.text | truncate($missing_var) }}"

      # Missing variables in function args should cause filter errors
      assert {:error, message} = Template.render(template, context)
      assert message =~ "Filter application failed" or message =~ "truncate"
    end
  end

  describe "advanced function scenarios" do
    setup do
      context = %{
        "$input" => %{
          "users" => [
            %{"name" => "Alice", "score" => 95.7},
            %{"name" => "Bob", "score" => 87.3}
          ],
          "config" => %{
            "precision" => 1,
            "currency" => "USD"
          }
        }
      }

      {:ok, context: context}
    end

    test "function calls within loops", %{context: context} do
      template =
        "{% for user in $input.users %}{{ user.name }}: {{ user.score | round($input.config.precision) }} {% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Alice: 95.7 Bob: 87.3 "
    end

    test "function calls in conditional expressions", %{context: context} do
      template = "{% if ($input.users | length()) > 1 %}Multiple users{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Multiple users"
    end

    test "complex nested function and expression combinations", %{context: context} do
      template = "{{ (($input.users | length()) * 10) | format_currency($input.config.currency) }}"

      assert {:ok, result} = Template.render(template, context)
      # 2 users * 10 = 20
      assert result == "$20.00"
    end

    test "function calls with deeply nested variable access", %{context: context} do
      template = "{{ $input.users | first() | get(\"score\") | round($input.config.precision) }}"

      # This test uses 'get' function which doesn't exist, so should return error
      assert {:error, message} = Template.render(template, context)
      assert message =~ "Unknown filter: get"
    end
  end
end
