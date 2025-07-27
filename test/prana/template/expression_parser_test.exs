defmodule Prana.Template.ExpressionParserTest do
  use ExUnit.Case, async: true

  alias Prana.Template.ExpressionParser

  describe "parse_filter_arguments with variables" do
    test "parses Prana expression variable arguments in filters" do
      expression = "$input.name | default($input.fallback)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.name"]},
        {:call, [], [:default, [{:variable, [], ["$input.fallback"]}]]}
      ]} = ast
    end

    test "parses unquoted identifier variable arguments" do
      expression = "$input.name | default(fallback_name)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.name"]},
        {:call, [], [:default, [{:variable, [], ["fallback_name"]}]]}
      ]} = ast
    end

    test "parses dotted variable paths" do
      expression = "$input.price | format_currency(config.currency)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.price"]},
        {:call, [], [:format_currency, [{:variable, [], ["config.currency"]}]]}
      ]} = ast
    end

    test "parses mixed literal and variable arguments" do
      expression = "$input.value | clamp($variables.min, 100)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.value"]},
        {:call, [], [:clamp, [
          {:variable, [], ["$variables.min"]},
          {:literal, [], [100]}
        ]]}
      ]} = ast
    end

    test "parses multiple variable arguments" do
      expression = "$input.items | slice($pagination.offset, $pagination.limit)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.items"]},
        {:call, [], [:slice, [
          {:variable, [], ["$pagination.offset"]},
          {:variable, [], ["$pagination.limit"]}
        ]]}
      ]} = ast
    end

    test "parses nested variable paths" do
      expression = "$input.name | default($nodes.api.default_name)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.name"]},
        {:call, [], [:default, [{:variable, [], ["$nodes.api.default_name"]}]]}
      ]} = ast
    end

    test "handles chained filters with variables" do
      expression = "$input.price | multiply($rates.conversion) | format_currency($locale.currency)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:pipe, [], [
          {:variable, [], ["$input.price"]},
          {:call, [], [:multiply, [{:variable, [], ["$rates.conversion"]}]]}
        ]},
        {:call, [], [:format_currency, [{:variable, [], ["$locale.currency"]}]]}
      ]} = ast
    end
  end

  describe "distinction between variables and literals" do
    test "quoted strings are parsed as literals" do
      expression = "$input.name | default(\"Unknown\")"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.name"]},
        {:call, [], [:default, [{:literal, [], ["Unknown"]}]]}
      ]} = ast
    end

    test "unquoted identifiers are parsed as variables" do
      expression = "$input.name | default(fallback_value)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.name"]},
        {:call, [], [:default, [{:variable, [], ["fallback_value"]}]]}
      ]} = ast
    end

    test "mixed quoted literals and unquoted variables" do
      expression = "$input.message | format(\"Hello %s\", user_name)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.message"]},
        {:call, [], [:format, [
          {:literal, [], ["Hello %s"]},
          {:variable, [], ["user_name"]}
        ]]}
      ]} = ast
    end
  end

  describe "backward compatibility with literal arguments" do
    test "still parses literal string arguments with quotes" do
      expression = "$input.name | default(\"Unknown\")"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.name"]},
        {:call, [], [:default, [{:literal, [], ["Unknown"]}]]}
      ]} = ast
    end

    test "still parses literal number arguments" do
      expression = "$input.age | add(5)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.age"]},
        {:call, [], [:add, [{:literal, [], [5]}]]}
      ]} = ast
    end

    test "still parses literal boolean arguments" do
      expression = "$input.value | default(true)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.value"]},
        {:call, [], [:default, [{:literal, [], [true]}]]}
      ]} = ast
    end

    test "handles filters without arguments" do
      expression = "$input.name | upper_case"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.name"]},
        {:call, [], [:upper_case, []]}
      ]} = ast
    end
  end

  describe "complex filter argument combinations" do
    test "handles quoted strings with spaces and variables" do
      expression = "$input.message | format(\"Hello %s\", $input.name, $config.suffix)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.message"]},
        {:call, [], [:format, [
          {:literal, [], ["Hello %s"]},
          {:variable, [], ["$input.name"]},
          {:variable, [], ["$config.suffix"]}
        ]]}
      ]} = ast
    end

    test "handles single quotes with variables" do
      expression = "$input.value | transform('prefix', $input.suffix)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.value"]},
        {:call, [], [:transform, [
          {:literal, [], ["prefix"]},
          {:variable, [], ["$input.suffix"]}
        ]]}
      ]} = ast
    end

    test "handles complex nested variable paths" do
      expression = "$input.user | get_property($config.fields.primary, $nodes.lookup.fallback_field)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.user"]},
        {:call, [], [:get_property, [
          {:variable, [], ["$config.fields.primary"]},
          {:variable, [], ["$nodes.lookup.fallback_field"]}
        ]]}
      ]} = ast
    end
  end

  describe "edge cases and error handling" do
    test "handles empty variable paths gracefully" do
      expression = "$input.name | default($)"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      # Should still parse but with minimal path
      assert {:pipe, [], [
        {:variable, [], ["$input.name"]},
        {:call, [], [:default, [{:variable, [], ["$"]}]]}
      ]} = ast
    end

    test "handles variables mixed with complex literals" do
      expression = "$input.data | transform(123.45, $input.multiplier, true, \"test\")"
      
      {:ok, ast} = ExpressionParser.parse(expression)
      
      assert {:pipe, [], [
        {:variable, [], ["$input.data"]},
        {:call, [], [:transform, [
          {:literal, [], [123.45]},
          {:variable, [], ["$input.multiplier"]},
          {:literal, [], [true]},
          {:literal, [], ["test"]}
        ]]}
      ]} = ast
    end
  end
end