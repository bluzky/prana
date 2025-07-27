defmodule Prana.Template.ExpressionParser do
  @moduledoc """
  Simple expression parser for template expressions.

  For now, this is a simplified version that focuses on the basic patterns.
  Can be enhanced with NimbleParsec later for more complex expressions.
  """

  alias Prana.Template.AST

  @doc """
  Parse an expression string into a standardized 3-tuple AST.

  Returns Elixir-style AST nodes in the format `{type, [], children}` where:
  - `type` is an atom representing the node type (`:variable`, `:literal`, `:binary_op`, `:pipe`, `:call`, `:grouped`)
  - The second element is always an empty list `[]` (metadata placeholder)
  - `children` is a list containing the node's data and child nodes

  ## Examples

      iex> parse("$input.age + 10")
      {:ok, {:binary_op, [], [:+, {:variable, [], ["$input.age"]}, {:literal, [], [10]}]}}
      
      iex> parse("$input.name | upper_case")
      {:ok, {:pipe, [], [{:variable, [], ["$input.name"]}, {:call, [], [:upper_case, []]}]}}
      
      iex> parse("42")
      {:ok, {:literal, [], [42]}}
      
      iex> parse("$input.name | default(\"Unknown\")")
      {:ok, {:pipe, [], [{:variable, [], ["$input.name"]}, {:call, [], [:default, [{:literal, [], ["Unknown"]}]]}]}}
  """
  @spec parse(String.t()) :: {:ok, tuple()} | {:error, String.t()}
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
          # Convert filters to chained pipe operations
          result_ast = Enum.reduce(filters, base_ast, fn filter, acc ->
            filter_ast = AST.call(String.to_atom(filter.name), filter.args)
            AST.pipe(acc, filter_ast)
          end)
          {:ok, result_ast}
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
    |> Enum.map(&parse_filter_argument/1)
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
          operator_atom = operator_to_atom(operator)
          {:ok, AST.binary_op(operator_atom, left_ast, right_ast)}
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

  defp operator_to_atom("+"), do: :+
  defp operator_to_atom("-"), do: :-
  defp operator_to_atom("*"), do: :*
  defp operator_to_atom("/"), do: :/
  defp operator_to_atom("=="), do: :==
  defp operator_to_atom("!="), do: :!=
  defp operator_to_atom(">="), do: :>=
  defp operator_to_atom("<="), do: :<=
  defp operator_to_atom(">"), do: :>
  defp operator_to_atom("<"), do: :<
  defp operator_to_atom("&&"), do: :&&
  defp operator_to_atom("||"), do: :||

  defp parse_simple_expression(expr) do
    expr = String.trim(expr)

    cond do
      # Variable path: $input.field -> should access context["$input"]["field"]
      String.starts_with?(expr, "$") ->
        {:ok, AST.variable(expr)}

      # String literal
      String.starts_with?(expr, "\"") and String.ends_with?(expr, "\"") ->
        content = String.slice(expr, 1..-2//1)
        {:ok, AST.literal(content)}

      String.starts_with?(expr, "'") and String.ends_with?(expr, "'") ->
        content = String.slice(expr, 1..-2//1)
        {:ok, AST.literal(content)}

      # Boolean literal
      expr == "true" ->
        {:ok, AST.literal(true)}

      expr == "false" ->
        {:ok, AST.literal(false)}

      # Number literal
      Regex.match?(~r/^\d+$/, expr) ->
        {:ok, AST.literal(String.to_integer(expr))}

      Regex.match?(~r/^\d+\.\d+$/, expr) ->
        {:ok, AST.literal(String.to_float(expr))}

      # Parentheses
      String.starts_with?(expr, "(") and String.ends_with?(expr, ")") ->
        inner = String.slice(expr, 1..-2//1)
        case parse(inner) do
          {:ok, inner_ast} -> {:ok, AST.grouped(inner_ast)}
          error -> error
        end

      # Default to string literal
      true ->
        {:ok, AST.literal(expr)}
    end
  end

  defp parse_filter_argument(str) do
    str = String.trim(str)

    cond do
      # Prana expression path: $input.field -> return AST structure  
      String.starts_with?(str, "$") ->
        AST.variable(str)

      # Quoted strings are literals
      (String.starts_with?(str, "\"") and String.ends_with?(str, "\"")) or
      (String.starts_with?(str, "'") and String.ends_with?(str, "'")) ->
        AST.literal(parse_literal(str))

      # Numbers and booleans are literals
      str in ["true", "false"] or Regex.match?(~r/^\d+(\.\d+)?$/, str) ->
        AST.literal(parse_literal(str))

      # Unquoted identifiers are variable references
      Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$/, str) ->
        AST.variable(str)

      # Default to literal parsing for edge cases
      true ->
        AST.literal(parse_literal(str))
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
