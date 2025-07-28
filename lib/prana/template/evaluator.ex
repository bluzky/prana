defmodule Prana.Template.Evaluator do
  @moduledoc """
  Expression evaluator for template expressions.

  Evaluates parsed expression ASTs by integrating with Prana.ExpressionEngine
  for variable path resolution and implementing arithmetic/boolean operations.
  """

  alias Prana.ExpressionEngine
  alias Prana.Template.FilterRegistry

  # Security limits
  # Max iterations in for loops
  @max_loop_iterations 10_000

  @doc """
  Evaluate a parsed expression AST against a context.

  ## Parameters
  - `ast` - Parsed expression AST from ExpressionParser
  - `context` - Context map for variable resolution

  ## Returns
  - `{:ok, value}` - Successfully evaluated value
  - `{:error, reason}` - Evaluation error

  ## Examples

      context = %{"$input" => %{"age" => 25, "name" => "John"}}

      # Variable access
      ast = {:variable, [], ["$input.age"]}
      {:ok, 25} = evaluate(ast, context)

      # Arithmetic
      ast = {:binary_op, [], [:+, {:variable, [], ["$input.age"]}, {:literal, [], [10]}]}
      {:ok, 35} = evaluate(ast, context)

      # With filters (pipe operations)
      ast = {:pipe, [], [{:variable, [], ["$input.name"]}, {:call, [], [:upper_case, []]}]}
      {:ok, "JOHN"} = evaluate(ast, context)
  """
  @spec evaluate(any(), map()) :: {:ok, any()} | {:error, String.t()}
  def evaluate(ast, context) when is_map(context) do
    case ast do
      # 3-tuple AST nodes
      {:variable, [], [path]} ->
        evaluate_variable_path(path, context)

      {:literal, [], [value]} ->
        {:ok, value}

      {:binary_op, [], [operator, left, right]} ->
        evaluate_binary_op(operator, left, right, context)

      {:pipe, [], [expression, function]} ->
        evaluate_pipe_expression(expression, function, context)

      {:call, [], [function_name, args]} ->
        evaluate_function_call(function_name, args, context)

      {:grouped, [], [inner_expression]} ->
        evaluate(inner_expression, context)

      {:for_loop, [], [variable, iterable, body]} ->
        evaluate_for_loop(variable, iterable, body, context)

      {:if_condition, [], [condition, then_body, else_body]} ->
        evaluate_if_condition(condition, then_body, else_body, context)

      # Direct values (for cases where literal values are passed directly)
      value when is_number(value) or is_boolean(value) or is_binary(value) ->
        {:ok, value}

      # Handle other literal types
      value ->
        {:ok, value}
    end
  end

  # Private functions

  defp evaluate_for_loop(variable, iterable, body, context) do
    with {:ok, collection} <- evaluate(iterable, context) do
      case collection do
        items when is_list(items) ->
          # Security check: limit loop iterations
          if length(items) > @max_loop_iterations do
            {:error, "For loop iterations (#{length(items)}) exceeds maximum allowed (#{@max_loop_iterations})"}
          else
            results =
              Enum.map(items, fn item ->
                # Create scoped context with loop variable accessible as $variable
                # Limit context exposure by only adding the loop variable
                scoped_context = Map.put(context, "$#{variable}", item)
                evaluate_body(body, scoped_context)
              end)

            # Flatten results and join as string for template rendering
            case flatten_results(results) do
              {:ok, flattened} -> {:ok, Enum.join(flattened, "")}
              error -> error
            end
          end

        _ ->
          {:error, "For loop iterable must be a list, got: #{inspect(collection)}"}
      end
    end
  end

  defp evaluate_if_condition(condition, then_body, else_body, context) do
    with {:ok, condition_result} <- evaluate(condition, context) do
      cond do
        truthy?(condition_result) ->
          evaluate_body(then_body, context)

        not Enum.empty?(else_body) ->
          evaluate_body(else_body, context)

        true ->
          {:ok, ""}
      end
    end
  end

  defp evaluate_body(body_blocks, context) do
    results =
      Enum.map(body_blocks, fn block ->
        case block do
          {:literal, content} ->
            {:ok, content}

          {:expression, content} ->
            # Parse and evaluate the expression
            alias Prana.Template.ExpressionParser

            case ExpressionParser.parse(content) do
              {:ok, ast} -> evaluate(ast, context)
              error -> error
            end

          {:control, type, attributes, body} ->
            # Parse and evaluate control block
            alias Prana.Template.ExpressionParser

            case ExpressionParser.parse_control_block(type, attributes, body) do
              {:ok, ast} -> evaluate(ast, context)
              error -> error
            end

          _ ->
            {:error, "Unknown block type: #{inspect(block)}"}
        end
      end)

    case flatten_results(results) do
      {:ok, flattened} -> {:ok, Enum.join(flattened, "")}
      error -> error
    end
  end

  defp flatten_results(results) do
    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil ->
        values = Enum.map(results, fn {:ok, value} -> to_string(value) end)
        {:ok, values}

      error ->
        error
    end
  end

  defp evaluate_binary_op(operator, left_ast, right_ast, context) do
    with {:ok, left_val} <- evaluate(left_ast, context),
         {:ok, right_val} <- evaluate(right_ast, context) do
      apply_operator(operator, left_val, right_val)
    end
  end

  defp evaluate_pipe_expression(expression, function, context) do
    with {:ok, value} <- evaluate(expression, context) do
      case function do
        {:call, [], [function_name, args]} ->
          with {:ok, evaluated_args} <- evaluate_args(args, context) do
            FilterRegistry.apply_filter(Atom.to_string(function_name), value, evaluated_args)
          end

        _ ->
          {:error, "Invalid pipe function"}
      end
    end
  end

  defp evaluate_function_call(function_name, args, context) do
    with {:ok, evaluated_args} <- evaluate_args(args, context) do
      FilterRegistry.apply_filter(Atom.to_string(function_name), nil, evaluated_args)
    end
  end

  defp evaluate_variable_path(path, context) do
    # Prana expression path (starts with $) - use ExpressionEngine
    if String.starts_with?(path, "$") do
      ExpressionEngine.extract(path, context)
    else
      # Simple variable name - look up directly in context, including scoped variables
      # First try direct access for scoped variables like "user"
      case Map.get(context, path) do
        nil ->
          # If not found directly, try path traversal for nested access like "user.name"
          case get_in(context, String.split(path, ".")) do
            nil -> {:ok, nil}
            value -> {:ok, value}
          end

        value ->
          {:ok, value}
      end
    end
  end

  defp evaluate_args(args, context) do
    results = Enum.map(args, fn arg -> evaluate(arg, context) end)

    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil ->
        values = Enum.map(results, fn {:ok, value} -> value end)
        {:ok, values}

      error ->
        error
    end
  end

  defp apply_operator(:+, left, right) when is_number(left) and is_number(right) do
    {:ok, left + right}
  end

  defp apply_operator(:-, left, right) when is_number(left) and is_number(right) do
    {:ok, left - right}
  end

  defp apply_operator(:*, left, right) when is_number(left) and is_number(right) do
    {:ok, left * right}
  end

  defp apply_operator(:/, left, right) when is_number(left) and is_number(right) do
    if right == 0 do
      {:error, "Division by zero"}
    else
      {:ok, left / right}
    end
  end

  # Comparison operators
  defp apply_operator(:>, left, right) when is_number(left) and is_number(right) do
    {:ok, left > right}
  end

  defp apply_operator(:<, left, right) when is_number(left) and is_number(right) do
    {:ok, left < right}
  end

  defp apply_operator(:>=, left, right) when is_number(left) and is_number(right) do
    {:ok, left >= right}
  end

  defp apply_operator(:<=, left, right) when is_number(left) and is_number(right) do
    {:ok, left <= right}
  end

  defp apply_operator(:==, left, right) do
    {:ok, left == right}
  end

  defp apply_operator(:!=, left, right) do
    {:ok, left != right}
  end

  # Logical operators (truthiness-based, suitable for template expressions)
  defp apply_operator(:&&, left, right) do
    {:ok, truthy?(left) && truthy?(right)}
  end

  defp apply_operator(:||, left, right) do
    {:ok, truthy?(left) || truthy?(right)}
  end

  # String concatenation with +
  defp apply_operator(:+, left, right) when is_binary(left) and is_binary(right) do
    {:ok, left <> right}
  end

  # Type coercion for mixed operations
  defp apply_operator(:+, left, right) when is_binary(left) do
    {:ok, left <> to_string(right)}
  end

  defp apply_operator(:+, left, right) when is_binary(right) do
    {:ok, to_string(left) <> right}
  end

  # Comparison with type coercion
  defp apply_operator(op, left, right) when op in [:>, :<, :>=, :<=] do
    case {coerce_to_number(left), coerce_to_number(right)} do
      {{:ok, left_num}, {:ok, right_num}} ->
        apply_operator(op, left_num, right_num)

      _ ->
        {:error, "Cannot compare #{inspect(left)} and #{inspect(right)}"}
    end
  end

  defp apply_operator(operator, left, right) do
    {:error, "Unsupported operation: #{inspect(left)} #{operator} #{inspect(right)}"}
  end

  # Helper functions

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(0), do: false
  defp truthy?(""), do: false
  defp truthy?([]), do: false
  defp truthy?(%{} = map) when map_size(map) == 0, do: false
  defp truthy?(_), do: true

  defp coerce_to_number(value) when is_number(value), do: {:ok, value}

  defp coerce_to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} ->
        {:ok, num}

      _ ->
        case Integer.parse(value) do
          {num, ""} -> {:ok, num}
          _ -> {:error, "Cannot convert to number"}
        end
    end
  end

  defp coerce_to_number(_), do: {:error, "Cannot convert to number"}
end
