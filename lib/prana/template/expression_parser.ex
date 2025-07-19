defmodule Prana.Template.ExpressionParser do
  @moduledoc """
  Simple expression parser for template expressions.

  For now, this is a simplified version that focuses on the basic patterns.
  Can be enhanced with NimbleParsec later for more complex expressions.
  """

  @doc """
  Parse an expression string into an AST.

  ## Examples

      iex> parse("$input.age + 10")
      {:ok, %{type: :binary_op, operator: "+", left: %{type: :variable, path: "$input.age"}, right: 10}}
      
      iex> parse("$input.name | upper_case")
      {:ok, %{type: :filtered, expression: %{type: :variable, path: "$input.name"}, filters: [%{name: "upper_case", args: []}]}}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(expression_string) when is_binary(expression_string) do
    expression_string = String.trim(expression_string)

    # Simple parsing approach - can be enhanced later
    cond do
      # Check for filters first (contains |)
      String.contains?(expression_string, "|") ->
        parse_filtered_expression(expression_string)

      # Check for binary operations
      has_binary_operator?(expression_string) ->
        parse_binary_expression(expression_string)

      # Simple variable or literal
      true ->
        parse_simple_expression(expression_string)
    end
  end

  # Private functions

  defp has_binary_operator?(expr) do
    # Simple check for common operators
    Enum.any?(["&&", "||", "==", "!=", ">=", "<=", ">", "<", "+", "-", "*", "/"], fn op ->
      String.contains?(expr, op)
    end)
  end

  defp parse_filtered_expression(expr) do
    case String.split(expr, "|", parts: 2) do
      [base_expr, filters_part] ->
        with {:ok, base_ast} <- parse_simple_expression(String.trim(base_expr)),
             {:ok, filters} <- parse_filters(String.trim(filters_part)) do
          {:ok, %{type: :filtered, expression: base_ast, filters: filters}}
        end

      _ ->
        {:error, "Invalid filter expression"}
    end
  end

  defp parse_filters(filters_str) do
    # Split on | but respect parentheses and quotes
    filter_parts = split_filters_smart(filters_str)

    filters =
      Enum.map(filter_parts, fn filter_str ->
        filter_str = String.trim(filter_str)

        case Regex.run(~r/^(\w+)(?:\(([^)]*)\))?$/, filter_str) do
          [_, name] ->
            %{name: name, args: []}

          [_, name, args_str] ->
            args = parse_filter_args(args_str)
            %{name: name, args: args}

          _ ->
            %{name: filter_str, args: []}
        end
      end)

    {:ok, filters}
  end

  defp split_filters_smart(filters_str) do
    # Split filters by | but respect parentheses
    split_filters(filters_str, [], "", 0, false, nil)
  end

  defp split_filters("", filters, current_filter, _paren_count, _in_quotes, _quote_char) do
    # End of string - add final filter if non-empty
    final_filters = if String.trim(current_filter) == "", do: filters, else: [current_filter | filters]
    Enum.reverse(final_filters)
  end

  defp split_filters(<<char, rest::binary>>, filters, current_filter, paren_count, in_quotes, quote_char) do
    cond do
      # Starting a quoted string
      not in_quotes and char in [?", ?'] ->
        split_filters(rest, filters, current_filter <> <<char>>, paren_count, true, char)

      # Ending a quoted string
      in_quotes and char == quote_char ->
        split_filters(rest, filters, current_filter <> <<char>>, paren_count, false, nil)

      # Open parenthesis outside quotes
      not in_quotes and char == ?( ->
        split_filters(rest, filters, current_filter <> <<char>>, paren_count + 1, false, nil)

      # Close parenthesis outside quotes
      not in_quotes and char == ?) ->
        split_filters(rest, filters, current_filter <> <<char>>, paren_count - 1, false, nil)

      # Pipe outside quotes and parentheses - split filter
      not in_quotes and paren_count == 0 and char == ?| ->
        new_filters = if String.trim(current_filter) == "", do: filters, else: [current_filter | filters]
        split_filters(rest, new_filters, "", 0, false, nil)

      # Any other character - add to current filter
      true ->
        split_filters(rest, filters, current_filter <> <<char>>, paren_count, in_quotes, quote_char)
    end
  end

  defp parse_filter_args(""), do: []

  defp parse_filter_args(args_str) do
    # Smart argument parsing - handle quoted strings with commas
    args_str
    |> parse_quoted_arguments()
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_literal/1)
  end

  defp parse_quoted_arguments(args_str) do
    # Parse arguments respecting quoted strings
    parse_arguments(args_str, [], "", false, nil)
  end

  defp parse_arguments("", args, current_arg, _in_quotes, _quote_char) do
    # End of string - add final argument if non-empty
    final_args = if String.trim(current_arg) == "", do: args, else: [current_arg | args]
    Enum.reverse(final_args)
  end

  defp parse_arguments(<<char, rest::binary>>, args, current_arg, in_quotes, quote_char) do
    cond do
      # Starting a quoted string
      not in_quotes and char in [?", ?'] ->
        parse_arguments(rest, args, current_arg <> <<char>>, true, char)

      # Ending a quoted string
      in_quotes and char == quote_char ->
        parse_arguments(rest, args, current_arg <> <<char>>, false, nil)

      # Comma outside quotes - split argument
      not in_quotes and char == ?, ->
        new_args = if String.trim(current_arg) == "", do: args, else: [current_arg | args]
        parse_arguments(rest, new_args, "", false, nil)

      # Any other character - add to current argument
      true ->
        parse_arguments(rest, args, current_arg <> <<char>>, in_quotes, quote_char)
    end
  end

  defp parse_binary_expression(expr) do
    # Find the main operator (rightmost for left-associativity)
    operators = ["||", "&&", "==", "!=", ">=", "<=", ">", "<", "+", "-", "*", "/"]

    case find_main_operator(expr, operators) do
      {operator, left_part, right_part} ->
        with {:ok, left_ast} <- parse(String.trim(left_part)),
             {:ok, right_ast} <- parse(String.trim(right_part)) do
          {:ok, %{type: :binary_op, operator: operator, left: left_ast, right: right_ast}}
        end

      nil ->
        parse_simple_expression(expr)
    end
  end

  defp find_main_operator(expr, operators) do
    # Find rightmost operator for left-associativity
    Enum.reduce_while(operators, nil, fn op, acc ->
      case String.split(expr, op, parts: 2) do
        [left, right] when left != expr ->
          {:halt, {op, left, right}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp parse_simple_expression(expr) do
    expr = String.trim(expr)

    cond do
      # Variable path: $input.field -> should access context["$input"]["field"]
      String.starts_with?(expr, "$") ->
        {:ok, %{type: :variable, path: expr}}

      # String literal
      String.starts_with?(expr, "\"") and String.ends_with?(expr, "\"") ->
        content = String.slice(expr, 1..-2//1)
        {:ok, content}

      String.starts_with?(expr, "'") and String.ends_with?(expr, "'") ->
        content = String.slice(expr, 1..-2//1)
        {:ok, content}

      # Boolean literal
      expr == "true" ->
        {:ok, true}

      expr == "false" ->
        {:ok, false}

      # Number literal
      Regex.match?(~r/^\d+$/, expr) ->
        {:ok, String.to_integer(expr)}

      Regex.match?(~r/^\d+\.\d+$/, expr) ->
        {:ok, String.to_float(expr)}

      # Parentheses
      String.starts_with?(expr, "(") and String.ends_with?(expr, ")") ->
        inner = String.slice(expr, 1..-2//1)
        parse(inner)

      # Default to string
      true ->
        {:ok, expr}
    end
  end

  defp parse_literal(str) do
    str = String.trim(str)

    cond do
      str == "true" -> true
      str == "false" -> false
      Regex.match?(~r/^\d+$/, str) -> String.to_integer(str)
      Regex.match?(~r/^\d+\.\d+$/, str) -> String.to_float(str)
      String.starts_with?(str, "\"") and String.ends_with?(str, "\"") -> String.slice(str, 1..-2//1)
      String.starts_with?(str, "'") and String.ends_with?(str, "'") -> String.slice(str, 1..-2//1)
      true -> str
    end
  end
end
