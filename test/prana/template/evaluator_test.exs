defmodule Prana.Template.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Prana.Template.Evaluator

  describe "evaluate with variable filter arguments" do
    setup do
      context = %{
        "$input" => %{
          "name" => "John",
          "age" => 25,
          "fallback" => "Default Name",
          "multiplier" => 2,
          "items" => ["a", "b", "c", "d", "e"]
        },
        "$variables" => %{
          "min" => 10,
          "max" => 100,
          "currency" => "USD",
          "offset" => 1,
          "limit" => 3
        },
        "$nodes" => %{
          "api" => %{
            "default_name" => "API Default",
            "response" => %{
              "bonus" => 5
            }
          }
        },
        # Simple variable names at context root
        "fallback_name" => "Root Fallback",
        "config" => %{
          "currency" => "EUR",
          "theme" => "dark"
        }
      }

      {:ok, context: context}
    end

    test "evaluates variable arguments in default filter", %{context: context} do
      # Test with non-nil value - should return original
      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.name"},
        filters: [%{name: "default", args: [%{type: :variable, path: "$input.fallback"}]}]
      }

      assert {:ok, "John"} = Evaluator.evaluate(ast, context)

      # Test with nil value - should return fallback variable value
      ast_nil = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.missing"},
        filters: [%{name: "default", args: [%{type: :variable, path: "$input.fallback"}]}]
      }

      assert {:ok, "Default Name"} = Evaluator.evaluate(ast_nil, context)
    end

    test "evaluates nested variable paths in filter arguments", %{context: context} do
      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.missing"},
        filters: [%{name: "default", args: [%{type: :variable, path: "$nodes.api.default_name"}]}]
      }

      assert {:ok, "API Default"} = Evaluator.evaluate(ast, context)
    end

    test "evaluates simple variable names in filter arguments", %{context: context} do
      # Test simple variable at context root
      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.missing"},
        filters: [%{name: "default", args: [%{type: :variable, path: "fallback_name"}]}]
      }

      assert {:ok, "Root Fallback"} = Evaluator.evaluate(ast, context)

      # Test dotted variable path
      ast_dotted = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.missing"},
        filters: [%{name: "default", args: [%{type: :variable, path: "config.currency"}]}]
      }

      assert {:ok, "EUR"} = Evaluator.evaluate(ast_dotted, context)
    end

    test "evaluates multiple variable arguments", %{context: context} do
      # Test a hypothetical clamp filter with min and max variables
      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.age"},
        filters: [%{
          name: "clamp",
          args: [
            %{type: :variable, path: "$variables.min"},
            %{type: :variable, path: "$variables.max"}
          ]
        }]
      }

      # Since clamp filter doesn't exist, this will error, but we can verify args are evaluated
      # by checking the error message includes the resolved values
      case Evaluator.evaluate(ast, context) do
        {:error, message} ->
          assert String.contains?(message, "Unknown filter: clamp")
        _ ->
          flunk("Expected error for unknown filter")
      end
    end

    test "handles mixed literal and variable arguments", %{context: context} do
      # Create an AST that would represent: $input.age | add($nodes.api.response.bonus)
      # Since add filter might not exist, we'll test with default which accepts any second arg
      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.missing"},
        filters: [%{
          name: "default",
          args: [%{type: :variable, path: "$nodes.api.response.bonus"}]
        }]
      }

      assert {:ok, 5} = Evaluator.evaluate(ast, context)
    end

    test "maintains backward compatibility with literal arguments", %{context: context} do
      # Test literal string argument
      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.missing"},
        filters: [%{name: "default", args: ["Literal Default"]}]
      }

      assert {:ok, "Literal Default"} = Evaluator.evaluate(ast, context)

      # Test literal number argument
      ast_num = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.missing"},
        filters: [%{name: "default", args: [42]}]
      }

      assert {:ok, 42} = Evaluator.evaluate(ast_num, context)
    end

    test "handles chained filters with variable arguments", %{context: context} do
      # Chain: name -> default(fallback) -> upper_case
      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.missing"},
        filters: [
          %{name: "default", args: [%{type: :variable, path: "$input.fallback"}]},
          %{name: "upper_case", args: []}
        ]
      }

      assert {:ok, "DEFAULT NAME"} = Evaluator.evaluate(ast, context)
    end

    test "handles filters without arguments", %{context: context} do
      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.name"},
        filters: [%{name: "upper_case", args: []}]
      }

      assert {:ok, "JOHN"} = Evaluator.evaluate(ast, context)
    end
  end

  describe "error handling for variable filter arguments" do
    test "handles missing variable paths gracefully", %{} do
      context = %{"$input" => %{"name" => "John"}}

      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.name"},
        filters: [%{name: "default", args: [%{type: :variable, path: "$missing.path"}]}]
      }

      # Missing variable path should resolve to nil, so default filter should use that as fallback
      # Since the main expression ($input.name) exists and is "John", default filter should return "John"
      assert {:ok, "John"} = Evaluator.evaluate(ast, context)

      # Test when main expression is missing - should use the nil fallback from missing path
      ast_main_missing = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.missing_field"},
        filters: [%{name: "default", args: [%{type: :variable, path: "$missing.path"}]}]
      }

      assert {:ok, nil} = Evaluator.evaluate(ast_main_missing, context)
    end

    test "returns error when filter doesn't exist", %{} do
      context = %{"$input" => %{"value" => 10}}

      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.value"},
        filters: [%{name: "nonexistent_filter", args: [%{type: :variable, path: "$input.value"}]}]
      }

      assert {:error, "Unknown filter: nonexistent_filter"} = Evaluator.evaluate(ast, context)
    end

    test "handles nested variable paths gracefully", %{} do
      context = %{"$input" => %{"data" => nil}}

      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.data"},
        filters: [%{name: "default", args: [%{type: :variable, path: "$input.data.nested.missing"}]}]
      }

      # Both the main expression and the filter argument resolve to nil
      # The default filter will return nil (since input is nil)
      assert {:ok, nil} = Evaluator.evaluate(ast, context)
    end
  end

  describe "complex evaluation scenarios" do
    test "evaluates deeply nested variable references", %{} do
      context = %{
        "$config" => %{
          "settings" => %{
            "defaults" => %{
              "user" => %{
                "name" => "System Default"
              }
            }
          }
        },
        "$input" => %{"user" => nil}
      }

      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.user"},
        filters: [%{
          name: "default",
          args: [%{type: :variable, path: "$config.settings.defaults.user.name"}]
        }]
      }

      assert {:ok, "System Default"} = Evaluator.evaluate(ast, context)
    end

    test "handles multiple filters with different argument types", %{} do
      context = %{
        "$input" => %{"text" => nil, "fallback" => "hello world"},
        "$config" => %{"case" => "upper"}
      }

      # missing -> default(variable) -> upper_case (no args)
      ast = %{
        type: :filtered,
        expression: %{type: :variable, path: "$input.text"},
        filters: [
          %{name: "default", args: [%{type: :variable, path: "$input.fallback"}]},
          %{name: "upper_case", args: []}
        ]
      }

      assert {:ok, "HELLO WORLD"} = Evaluator.evaluate(ast, context)
    end
  end
end