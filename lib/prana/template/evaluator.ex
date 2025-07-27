defmodule Prana.Template.Evaluator do
  @moduledoc """
  Expression evaluator for template expressions.

  Evaluates parsed expression ASTs by integrating with Prana.ExpressionEngine
  for variable path resolution and implementing arithmetic/boolean operations.
  """

  alias Prana.ExpressionEngine
  alias Prana.Template.FilterRegistry

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

      # Direct values (for cases where literal values are passed directly)
      value when is_number(value) or is_boolean(value) or is_binary(value) ->
        {:ok, value}

      # Handle other literal types
      value ->
        {:ok, value}
    end
  end

  # Private functions

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
    cond do
      # Prana expression path (starts with $) - use ExpressionEngine
      String.starts_with?(path, "$") ->
        ExpressionEngine.extract(path, context)

      # Simple variable name - look up directly in context
      true ->
        case get_in(context, String.split(path, ".")) do
          nil -> {:ok, nil}
          value -> {:ok, value}
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
