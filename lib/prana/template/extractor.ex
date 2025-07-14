defmodule Prana.Template.Extractor do
  @moduledoc """
  Template block extraction for {{ }} expressions.

  Extracts template blocks from template strings, separating literal text
  from expression blocks that need to be evaluated.
  """

  @doc """
  Extract template blocks from a template string.

  Returns a list of blocks where each block is either:
  - `{:literal, text}` - Literal text to include as-is
  - `{:expression, content}` - Expression content to be parsed and evaluated

  ## Examples

      iex> extract("Hello {{ $input.name }}!")
      [{:literal, "Hello "}, {:expression, " $input.name "}, {:literal, "!"}]
      
      iex> extract("{{ $input.age + 10 | round }}")
      [{:expression, " $input.age + 10 | round "}]
      
      iex> extract("No expressions here")
      [{:literal, "No expressions here"}]
  """
  @spec extract(String.t()) :: [{:literal | :expression, String.t()}] | {:error, String.t()}
  def extract(template) when is_binary(template) do
    case validate_template_syntax(template) do
      :ok ->
        {:ok, do_extract(template)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a string contains template expressions.

  ## Examples

      iex> has_expressions?("Hello {{ $input.name }}")
      true
      
      iex> has_expressions?("No expressions")
      false
  """
  @spec has_expressions?(String.t()) :: boolean()
  def has_expressions?(template) when is_binary(template) do
    String.contains?(template, "{{") and String.contains?(template, "}}")
  end

  # Private functions

  defp validate_template_syntax(template) do
    open_count = count_occurrences(template, "{{")
    close_count = count_occurrences(template, "}}")

    cond do
      open_count != close_count ->
        {:error, "Mismatched template braces: #{open_count} opening, #{close_count} closing"}

      has_nested_braces?(template) ->
        {:error, "Nested template expressions are not supported"}

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
    Regex.match?(~r/\{\{[^}]*\{\{/, template)
  end

  defp do_extract(template) do
    # Split on {{ and }} while preserving delimiters
    parts = Regex.split(~r/(\{\{|\}\})/, template, include_captures: true)

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
