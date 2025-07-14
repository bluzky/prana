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
      ast = %{type: :variable, path: "$input.age"}
      {:ok, 25} = evaluate(ast, context)
      
      # Arithmetic
      ast = %{type: :binary_op, operator: :+, left: %{type: :variable, path: "$input.age"}, right: 10}
      {:ok, 35} = evaluate(ast, context)
      
      # With filters
      ast = %{type: :filtered, expression: %{type: :variable, path: "$input.name"}, filters: [%{name: "upper_case", args: []}]}
      {:ok, "JOHN"} = evaluate(ast, context)
  """
  @spec evaluate(any(), map()) :: {:ok, any()} | {:error, String.t()}
  def evaluate(ast, context) when is_map(context) do
    case ast do
      %{type: :variable, path: path} ->
        # Delegate to existing ExpressionEngine
        ExpressionEngine.extract(path, context)

      %{type: :binary_op, operator: op, left: left, right: right} ->
        evaluate_binary_op(op, left, right, context)

      %{type: :filtered, expression: expr, filters: filters} ->
        evaluate_filtered_expression(expr, filters, context)

      # Literals (direct values from parser)
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

  # Handle both string and atom operators for compatibility
  defp apply_operator(op, left, right) when is_binary(op) do
    atom_op =
      case op do
        "+" -> :+
        "-" -> :-
        "*" -> :*
        "/" -> :/
        ">" -> :>
        "<" -> :<
        ">=" -> :>=
        "<=" -> :<=
        "==" -> :==
        "!=" -> :!=
        "&&" -> :&&
        "||" -> :||
        _ -> String.to_atom(op)
      end

    apply_operator(atom_op, left, right)
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

  # Logical operators
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

  defp evaluate_filtered_expression(expr_ast, filters, context) do
    # First evaluate the base expression
    with {:ok, value} <- evaluate(expr_ast, context) do
      # Apply filters in sequence
      apply_filters(value, filters)
    end
  end

  defp apply_filters(value, []), do: {:ok, value}

  defp apply_filters(value, [filter | remaining_filters]) do
    case apply_single_filter(value, filter) do
      {:ok, filtered_value} ->
        apply_filters(filtered_value, remaining_filters)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_single_filter(value, %{name: filter_name, args: args}) do
    FilterRegistry.apply_filter(filter_name, value, args)
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
