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

  describe "control flow evaluation" do
    setup do
      context = %{
        "$input" => %{
          "users" => [
            %{"name" => "Alice", "age" => 25, "active" => true},
            %{"name" => "Bob", "age" => 17, "active" => false}
          ],
          "age" => 25,
          "status" => "premium"
        }
      }

      {:ok, context: context}
    end

    test "evaluates for loop with simple iteration", %{context: context} do
      # {:for_loop, [], [variable, iterable, body]}
      iterable_ast = {:variable, [], ["$input.users"]}
      body_blocks = [
        {:literal, "User: "},
        {:expression, " $user.name "},
        {:literal, " "}
      ]

      ast = {:for_loop, [], ["user", iterable_ast, body_blocks]}

      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert result == "User: Alice User: Bob "
    end

    test "evaluates for loop with empty collection", %{context: _context} do
      context = %{"$input" => %{"empty_list" => []}}

      iterable_ast = {:variable, [], ["$input.empty_list"]}
      body_blocks = [{:literal, "Item"}]

      ast = {:for_loop, [], ["item", iterable_ast, body_blocks]}

      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert result == ""
    end

    test "evaluates if condition with true condition", %{context: context} do
      # {:if_condition, [], [condition, then_body, else_body]}
      condition_ast = {:binary_op, [], [:>=, {:variable, [], ["$input.age"]}, {:literal, [], [18]}]}
      then_body = [{:literal, "Welcome adult!"}]
      else_body = [{:literal, "Must be 18+"}]

      ast = {:if_condition, [], [condition_ast, then_body, else_body]}

      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert result == "Welcome adult!"
    end

    test "evaluates if condition with false condition", %{context: _context} do
      context = %{"$input" => %{"age" => 16}}

      condition_ast = {:binary_op, [], [:>=, {:variable, [], ["$input.age"]}, {:literal, [], [18]}]}
      then_body = [{:literal, "Welcome adult!"}]
      else_body = [{:literal, "Must be 18+"}]

      ast = {:if_condition, [], [condition_ast, then_body, else_body]}

      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert result == "Must be 18+"
    end

    test "evaluates if condition with no else body", %{context: _context} do
      context = %{"$input" => %{"age" => 16}}

      condition_ast = {:binary_op, [], [:>=, {:variable, [], ["$input.age"]}, {:literal, [], [18]}]}
      then_body = [{:literal, "Welcome adult!"}]
      else_body = []

      ast = {:if_condition, [], [condition_ast, then_body, else_body]}

      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert result == ""
    end

    test "handles for loop with non-list iterable", %{context: _context} do
      context = %{"$input" => %{"not_list" => "string"}}

      iterable_ast = {:variable, [], ["$input.not_list"]}
      body_blocks = [{:literal, "Item"}]

      ast = {:for_loop, [], ["item", iterable_ast, body_blocks]}

      assert {:error, reason} = Evaluator.evaluate(ast, context)
      assert reason =~ "For loop iterable must be a list"
    end

    test "evaluates nested control flow in loop body", %{context: context} do
      # Loop through users, show different message based on age
      iterable_ast = {:variable, [], ["$input.users"]}

      # Body contains if condition using $user syntax
      then_body = [{:literal, "Adult: "}, {:expression, " $user.name "}]
      else_body = [{:literal, "Minor: "}, {:expression, " $user.name "}]

      if_block = {:control, :if_condition, %{condition: "$user.age >= 18"}, %{then_body: then_body, else_body: else_body}}
      body_blocks = [if_block, {:literal, " "}]

      ast = {:for_loop, [], ["user", iterable_ast, body_blocks]}

      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert result == "Adult: Alice Minor: Bob "
    end
  end
end