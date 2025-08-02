defmodule Prana.Template.Parser do
  @moduledoc """
  NimbleParsec-based template parser.

  Parses template strings into AST blocks for evaluation.
  Supports:
  - {{ expression }} - Expression blocks
  - {% if condition %}...{% endif %} - Conditional blocks
  - {% for item in collection %}...{% endfor %} - Loop blocks
  """

  import NimbleParsec

  # Template delimiters
  expression_start = "{{" |> string() |> ignore()
  expression_end = "}}" |> string() |> ignore()

  control_start = "{%" |> string() |> ignore()
  control_end = "%}" |> string() |> ignore()

  # Whitespace handling
  whitespace = ignore(repeat(ascii_char([?\s, ?\t, ?\n, ?\r])))

  # Expression content (everything between {{ }})
  expression_content =
    expression_end
    |> lookahead_not()
    |> utf8_char([])
    |> repeat()
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:expression)

  # Expression block
  expression_block =
    expression_start
    |> concat(expression_content)
    |> concat(expression_end)

  # Control flow tags
  if_tag =
    control_start
    |> concat(whitespace)
    |> ignore(string("if"))
    |> concat(whitespace)
    |> repeat(
      control_end
      |> lookahead_not()
      |> utf8_char([])
    )
    |> reduce({List, :to_string, []})
    |> concat(whitespace)
    |> concat(control_end)
    |> unwrap_and_tag(:if_start)

  endif_tag =
    control_start
    |> concat(whitespace)
    |> ignore(string("endif"))
    |> concat(whitespace)
    |> concat(control_end)
    |> replace({:endif})

  for_tag =
    control_start
    |> concat(whitespace)
    |> ignore(string("for"))
    |> concat(whitespace)
    |> repeat(
      control_end
      |> lookahead_not()
      |> utf8_char([])
    )
    |> reduce({List, :to_string, []})
    |> concat(whitespace)
    |> concat(control_end)
    |> unwrap_and_tag(:for_start)

  endfor_tag =
    control_start
    |> concat(whitespace)
    |> ignore(string("endfor"))
    |> concat(whitespace)
    |> concat(control_end)
    |> replace({:endfor})

  # Literal text (everything not in expression or control blocks)
  literal_text =
    [expression_start, control_start]
    |> choice()
    |> lookahead_not()
    |> utf8_char([])
    |> times(min: 1)
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:literal)

  # Template parsing
  template_parser =
    repeat(
      choice([
        expression_block,
        if_tag,
        endif_tag,
        for_tag,
        endfor_tag,
        literal_text
      ])
    )

  defparsec(:parse_template, template_parser)

  @spec parse(String.t()) :: {:ok, list()} | {:error, String.t()}
  def parse(template_string) when is_binary(template_string) do
    case parse_template(template_string) do
      {:ok, tokens, "", _, _, _} ->
        case build_ast(tokens) do
          {:ok, ast} -> {:ok, ast}
          {:error, reason} -> {:error, reason}
        end

      {:ok, tokens, remainder, _, _, _} ->
        # Add remaining text as literal
        tokens_with_remainder = tokens ++ [{:literal, remainder}]

        case build_ast(tokens_with_remainder) do
          {:ok, ast} -> {:ok, ast}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason, _remainder, _context, _line, _column} ->
        {:error, "Template parsing failed: #{inspect(reason)}"}
    end
  end

  # Build structured AST from flat token list
  defp build_ast(tokens) do
    {ast, []} = build_ast_recursive(tokens, [])
    {:ok, ast}
  rescue
    error -> {:error, "AST building failed: #{inspect(error)}"}
  catch
    {:error, message} -> {:error, message}
  end

  defp build_ast_recursive([], acc), do: {Enum.reverse(acc), []}

  defp build_ast_recursive([{:if_start, condition} | rest], acc) do
    {body, remaining} = build_ast_until_token(rest, :endif, [])
    {final_remaining, _} = consume_token(remaining, :endif)

    control_block = {:control, :if, String.trim(condition), body}
    build_ast_recursive(final_remaining, [control_block | acc])
  end

  defp build_ast_recursive([{:for_start, loop_spec} | rest], acc) do
    {body, remaining} = build_ast_until_token(rest, :endfor, [])
    {final_remaining, _} = consume_token(remaining, :endfor)

    control_block = {:control, :for, String.trim(loop_spec), body}
    build_ast_recursive(final_remaining, [control_block | acc])
  end

  defp build_ast_recursive([{:endif} | _rest], _acc) do
    throw({:error, "Unexpected endif tag without matching if"})
  end

  defp build_ast_recursive([{:endfor} | _rest], _acc) do
    throw({:error, "Unexpected endfor tag without matching for"})
  end

  defp build_ast_recursive([token | rest], acc) do
    build_ast_recursive(rest, [token | acc])
  end

  defp build_ast_until_token([], _end_token, _acc) do
    throw({:error, "Reached end of tokens without finding expected end tag"})
  end

  defp build_ast_until_token([{end_token} | rest], end_token, acc) when is_atom(end_token) do
    {Enum.reverse(acc), [{end_token} | rest]}
  end

  defp build_ast_until_token([{:if_start, condition} | rest], end_token, acc) do
    # Handle nested if blocks
    {nested_body, remaining} = build_ast_until_token(rest, :endif, [])
    {remaining_after_endif, _} = consume_token(remaining, :endif)

    nested_control = {:control, :if, String.trim(condition), nested_body}
    build_ast_until_token(remaining_after_endif, end_token, [nested_control | acc])
  end

  defp build_ast_until_token([{:for_start, loop_spec} | rest], end_token, acc) do
    # Handle nested for blocks
    {nested_body, remaining} = build_ast_until_token(rest, :endfor, [])
    {remaining_after_endfor, _} = consume_token(remaining, :endfor)

    nested_control = {:control, :for, String.trim(loop_spec), nested_body}
    build_ast_until_token(remaining_after_endfor, end_token, [nested_control | acc])
  end

  defp build_ast_until_token([token | rest], end_token, acc) do
    build_ast_until_token(rest, end_token, [token | acc])
  end

  defp consume_token([{token} | rest], token) when is_atom(token), do: {rest, token}

  defp consume_token(tokens, expected_token) do
    throw({:error, "Expected #{expected_token}, but got #{inspect(tokens)}"})
  end
end
