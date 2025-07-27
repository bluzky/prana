defmodule Prana.Template.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Prana.Template.Evaluator

  describe "evaluate with 3-tuple AST" do
    setup do
      context = %{
        "$input" => %{
          "name" => "John",
          "age" => 25,
          "missing" => nil
        },
        "$nodes" => %{
          "api" => %{
            "default_name" => "API Default"
          }
        },
        "fallback_name" => "Simple Fallback"
      }

      {:ok, context: context}
    end

    test "evaluates literal values", %{context: context} do
      assert {:ok, 42} = Evaluator.evaluate({:literal, [], [42]}, context)
      assert {:ok, "hello"} = Evaluator.evaluate({:literal, [], ["hello"]}, context)
      assert {:ok, true} = Evaluator.evaluate({:literal, [], [true]}, context)
    end

    test "evaluates variable paths", %{context: context} do
      # Dollar paths
      assert {:ok, "John"} = Evaluator.evaluate({:variable, [], ["$input.name"]}, context)
      assert {:ok, 25} = Evaluator.evaluate({:variable, [], ["$input.age"]}, context)
      assert {:ok, nil} = Evaluator.evaluate({:variable, [], ["$input.missing"]}, context)
      
      # Simple paths
      assert {:ok, "Simple Fallback"} = Evaluator.evaluate({:variable, [], ["fallback_name"]}, context)
    end

    test "evaluates binary operations", %{context: context} do
      # Arithmetic
      ast = {:binary_op, [], [:+, {:variable, [], ["$input.age"]}, {:literal, [], [10]}]}
      assert {:ok, 35} = Evaluator.evaluate(ast, context)
      
      # Comparison
      ast = {:binary_op, [], [:>=, {:variable, [], ["$input.age"]}, {:literal, [], [18]}]}
      assert {:ok, true} = Evaluator.evaluate(ast, context)
      
      # Logical
      ast = {:binary_op, [], [:&&, {:literal, [], [true]}, {:literal, [], [false]}]}
      assert {:ok, false} = Evaluator.evaluate(ast, context)
    end

    test "evaluates pipe operations", %{context: context} do
      # Simple filter
      ast = {:pipe, [], [
        {:variable, [], ["$input.name"]},
        {:call, [], [:upper_case, []]}
      ]}
      assert {:ok, "JOHN"} = Evaluator.evaluate(ast, context)
      
      # Filter with arguments
      ast = {:pipe, [], [
        {:variable, [], ["$input.missing"]},
        {:call, [], [:default, [{:variable, [], ["fallback_name"]}]]}
      ]}
      assert {:ok, "Simple Fallback"} = Evaluator.evaluate(ast, context)
    end

    test "evaluates function calls", %{context: context} do
      # Function with arguments
      ast = {:call, [], [:default, [{:literal, [], ["test"]}]]}
      assert {:ok, "test"} = Evaluator.evaluate(ast, context)
    end

    test "evaluates grouped expressions", %{context: context} do
      inner = {:binary_op, [], [:+, {:literal, [], [2]}, {:literal, [], [3]}]}
      ast = {:grouped, [], [inner]}
      assert {:ok, 5} = Evaluator.evaluate(ast, context)
    end

    test "evaluates direct values for backward compatibility", %{context: context} do
      assert {:ok, 42} = Evaluator.evaluate(42, context)
      assert {:ok, "hello"} = Evaluator.evaluate("hello", context)
      assert {:ok, true} = Evaluator.evaluate(true, context)
    end
  end

  describe "error handling" do
    test "handles invalid operations" do
      context = %{}
      ast = {:binary_op, [], [:+, {:literal, [], ["hello"]}, {:literal, [], ["world"]}]}
      assert {:ok, "helloworld"} = Evaluator.evaluate(ast, context)
    end

    test "handles missing variables gracefully" do
      context = %{}
      ast = {:variable, [], ["$missing.path"]}
      assert {:ok, nil} = Evaluator.evaluate(ast, context)
    end
  end
end