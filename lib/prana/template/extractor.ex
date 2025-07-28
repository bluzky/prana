defmodule Prana.Template.Extractor do
  @moduledoc """
  Template block extraction for {{ }} expressions and {% %} control flow blocks.

  Extracts template blocks from template strings, separating literal text
  from expression blocks and control flow blocks that need to be evaluated.
  """

  # Cached regex patterns for performance and ReDoS protection
  @expression_delim_regex ~r/(\{\{|\}\})/
  @control_block_regex ~r/^(.*?)\{%\s*(for|if)\s+([^%]+)%\}(.*?)\{%\s*end\2\s*%\}(.*)$/s
  @for_variable_regex ~r/(\w+)\s+in\s+(.+)/
  @nested_braces_regex ~r/\{\{[^}]*\{\{/
  @control_validation_regex ~r/\{%\s*(\w+)[^%]*%\}.*?\{%\s*end\1\s*%\}/s
  @for_blocks_regex ~r/\{%\s*for\s+\w+\s+in\s+[^%]+%\}.*?\{%\s*endfor\s*%\}/s
  @if_blocks_regex ~r/\{%\s*if\s+[^%]+%\}.*?\{%\s*endif\s*%\}/s

  @doc """
  Extract template blocks from a template string.

  Returns a list of blocks where each block is either:
  - `{:literal, text}` - Literal text to include as-is
  - `{:expression, content}` - Expression content to be parsed and evaluated
  - `{:control, type, attributes, body}` - Control flow block (for loops, if conditions)

  ## Examples

      iex> extract("Hello {{ $input.name }}!")
      [{:literal, "Hello "}, {:expression, " $input.name "}, {:literal, "!"}]

      iex> extract("{{ $input.age + 10 | round }}")
      [{:expression, " $input.age + 10 | round "}]

      iex> extract("{% for user in $input.users %}{{ user.name }}{% endfor %}")
      [{:control, :for_loop, %{variable: "user", iterable: "$input.users"}, [{:expression, " user.name "}]}]

      iex> extract("No expressions here")
      [{:literal, "No expressions here"}]
  """
  @spec extract(String.t()) :: [{:literal | :expression | :control, any()}] | {:error, String.t()}
  def extract(template) when is_binary(template) do
    case validate_template_syntax(template) do
      :ok ->
        {:ok, do_extract(template)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a string contains template expressions or control flow blocks.

  ## Examples

      iex> has_expressions?("Hello {{ $input.name }}")
      true

      iex> has_expressions?("{% for user in users %}...{% endfor %}")
      true

      iex> has_expressions?("No expressions")
      false
  """
  @spec has_expressions?(String.t()) :: boolean()
  def has_expressions?(template) when is_binary(template) do
    has_expression_blocks?(template) or has_control_blocks?(template)
  end

  defp has_expression_blocks?(template) do
    String.contains?(template, "{{") and String.contains?(template, "}}")
  end

  defp has_control_blocks?(template) do
    String.contains?(template, "{%") and String.contains?(template, "%}")
  end

  # Private functions

  defp validate_template_syntax(template) do
    with :ok <- validate_expression_syntax(template) do
      validate_control_flow_syntax(template)
    end
  end

  defp validate_expression_syntax(template) do
    open_count = count_occurrences(template, "{{")
    close_count = count_occurrences(template, "}}")

    cond do
      open_count != close_count ->
        {:error, "Mismatched expression braces: #{open_count} opening, #{close_count} closing"}

      has_nested_braces?(template) ->
        {:error, "Nested template expressions are not supported"}

      true ->
        :ok
    end
  end

  defp validate_control_flow_syntax(template) do
    open_count = count_occurrences(template, "{%")
    close_count = count_occurrences(template, "%}")

    cond do
      open_count != close_count ->
        {:error, "Mismatched control flow braces: #{open_count} opening, #{close_count} closing"}

      not valid_control_blocks?(template) ->
        {:error, "Invalid or mismatched control flow blocks"}

      true ->
        :ok
    end
  end

  defp count_occurrences(string, pattern) do
    string
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end

  defp has_nested_braces?(template) do
    # Check for {{ inside {{ }} blocks
    Regex.match?(@nested_braces_regex, template)
  end

  defp valid_control_blocks?(template) do
    # Extract all control flow blocks and validate their structure
    control_blocks = Regex.scan(@control_validation_regex, template)

    # Check for proper for/endfor and if/endif matching
    for_blocks = Regex.scan(@for_blocks_regex, template)
    if_blocks = Regex.scan(@if_blocks_regex, template)

    # All control blocks should be either for/endfor or if/endif pairs
    length(control_blocks) == length(for_blocks) + length(if_blocks)
  end

  defp do_extract(template) do
    # First extract control flow blocks, then process remaining template
    case extract_control_blocks(template) do
      {[], remaining_template} ->
        # No control blocks, just extract expressions
        extract_expressions(remaining_template)

      {control_blocks, _} ->
        # Has control blocks, process them
        control_blocks
    end
  end

  defp extract_control_blocks(template) do
    # Look for control flow blocks first
    case Regex.run(@control_block_regex, template) do
      [_full, before, type, attributes, body, remaining] ->
        # Parse the control block
        control_block = parse_control_block(type, String.trim(attributes), body)

        # Recursively process before and remaining parts
        before_blocks = if before == "", do: [], else: extract_expressions(before)
        remaining_blocks = if remaining == "", do: [], else: do_extract(remaining)

        {before_blocks ++ [control_block] ++ remaining_blocks, ""}

      nil ->
        # No control blocks found
        {[], template}
    end
  end

  defp parse_control_block("for", attributes, body) do
    # Parse "user in $input.users" format
    case Regex.run(@for_variable_regex, attributes) do
      [_full, variable, iterable] ->
        body_blocks = extract_expressions(body)
        {:control, :for_loop, %{variable: String.trim(variable), iterable: String.trim(iterable)}, body_blocks}

      _ ->
        {:error, "Invalid for loop syntax: #{attributes}"}
    end
  end

  defp parse_control_block("if", attributes, body) do
    # For now, handle simple if without else
    body_blocks = extract_expressions(body)
    {:control, :if_condition, %{condition: String.trim(attributes)}, %{then_body: body_blocks, else_body: []}}
  end

  defp extract_expressions(template) do
    # Split on {{ and }} while preserving delimiters
    parts = Regex.split(@expression_delim_regex, template, include_captures: true)

    # Process parts into blocks
    {blocks, _state} =
      Enum.reduce(parts, {[], :literal}, fn part, {acc, state} ->
        case {part, state} do
          {"{{", :literal} ->
            {acc, :expression}

          {"}}", :expression} ->
            {acc, :literal}

          {content, :literal} when content != "" ->
            {acc ++ [{:literal, content}], :literal}

          {content, :expression} when content != "" ->
            {acc ++ [{:expression, content}], :expression}

          {"", _} ->
            {acc, state}

          _ ->
            {acc, state}
        end
      end)

    # Filter out empty blocks and return
    Enum.reject(blocks, fn
      {:literal, ""} -> true
      {:expression, ""} -> true
      _ -> false
    end)
  end
end
