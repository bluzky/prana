defmodule Prana.Template.Engine do
  @moduledoc """
  Main template engine API for rendering templates with expressions and filters.

  Provides the primary interface for template rendering, integrating all components:
  - Template extraction
  - Expression parsing
  - Expression evaluation
  - Filter application

  ## Usage

      # Simple variable interpolation
      context = %{"$input" => %{"name" => "John"}}
      {:ok, "Hello John!"} = render("Hello {{ $input.name }}!", context)

      # Arithmetic expressions
      context = %{"$input" => %{"age" => 25}}
      {:ok, "Age in 10 years: 35"} = render("Age in 10 years: {{ $input.age + 10 }}", context)

      # Boolean expressions
      context = %{"$input" => %{"age" => 25, "verified" => true}}
      {:ok, "Eligible: true"} = render("Eligible: {{ $input.age >= 18 && $input.verified }}", context)

      # Filters
      context = %{"$input" => %{"name" => "john"}}
      {:ok, "Hello JOHN!"} = render("Hello {{ $input.name | upper_case }}!", context)
  """
  alias Prana.Template.Evaluator
  alias Prana.Template.ExpressionParser
  alias Prana.Template.Extractor

  require Logger

  @doc """
  Render a template string with the given context.

  ## Parameters
  - `template_string` - Template string containing expressions
  - `context` - Context map for variable resolution
  - `opts` - Options (currently unused, for future extensibility)

  ## Returns
  - `{:ok, rendered_string}` - Successfully rendered template
  - `{:error, reason}` - Rendering error with details

  ## Examples

      context = %{
        "$input" => %{
          "user" => %{"name" => "John", "age" => 35},
          "price" => 99.99,
          "verified" => true
        }
      }

      # Basic interpolation
      {:ok, "Hello John!"} = render("Hello {{ $input.user.name }}!", context)

      # Arithmetic with filters
      {:ok, "Price: $104.99"} = render("Price: {{ ($input.price + 5) | format_currency('USD') }}", context)

      # Boolean expressions
      {:ok, "Eligible: true"} = render("Eligible: {{ $input.user.age >= 18 && $input.verified }}", context)

      # Filter chaining
      {:ok, "JOH"} = render("{{ $input.user.name | upper_case | truncate(3) }}", context)
  """
  @spec render(String.t(), map(), keyword()) :: {:ok, any()} | {:error, String.t()}
  def render(template_string, context, _opts \\ []) when is_binary(template_string) and is_map(context) do
    # Extract template blocks once
    case Extractor.extract(template_string) do
      {:ok, blocks} ->
        # Check if this is a pure expression and render accordingly
        if is_pure_expression_blocks?(blocks) do
          render_pure_expression_from_blocks(blocks, context)
        else
          render_blocks_as_string(blocks, context)
        end

      {:error, reason} ->
        {:error, "Template extraction failed: #{reason}"}
    end
  end

  # Private functions

  defp is_pure_expression_blocks?(blocks) do
    # Pure expression = exactly one expression block, no literal text at all
    case blocks do
      [{:expression, _content}] -> true
      _ -> false
    end
  end

  defp render_pure_expression_from_blocks([{:expression, expression_content}], context) do
    # Parse and evaluate the single expression, returning original data type
    case ExpressionParser.parse(String.trim(expression_content)) do
      {:ok, ast} ->
        case Evaluator.evaluate(ast, context) do
          {:ok, value} ->
            {:ok, value}

          {:error, reason} ->
            # For pure expressions, return the original expression as string when evaluation fails
            Logger.error("Expression evaluation failed: #{reason}")
            {:ok, "{{#{expression_content}}}"}
        end

      {:error, reason} ->
        # Return original expression when parsing fails
        Logger.error("Expression evaluation failed: #{reason}")
        {:ok, "{{#{expression_content}}}"}
    end
  end

  defp render_blocks_as_string(blocks, context) do
    rendered_parts =
      Enum.map(blocks, fn block ->
        case render_single_block(block, context) do
          {:ok, content} -> content
        end
      end)

    {:ok, Enum.join(rendered_parts, "")}
  end

  defp render_single_block({:literal, text}, _context) do
    {:ok, text}
  end

  defp render_single_block({:expression, expression_content}, context) do
    # Parse the expression content
    case ExpressionParser.parse(String.trim(expression_content)) do
      {:ok, ast} ->
        # Evaluate the parsed AST
        case Evaluator.evaluate(ast, context) do
          {:ok, value} ->
            {:ok, format_output_value(value)}

          {:error, reason} ->
            # Return original expression when evaluation fails (parsing errors, etc.)
            Logger.error("Expression evaluation failed: #{reason}")
            {:ok, "{{#{expression_content}}}"}
        end

      {:error, reason} ->
        Logger.error("Expression evaluation failed: #{reason}")
        # Return original expression when parsing fails
        {:ok, "{{#{expression_content}}}"}
    end
  end

  defp format_output_value(nil), do: ""
  defp format_output_value(value) when is_binary(value), do: value
  defp format_output_value(value) when is_number(value), do: to_string(value)
  defp format_output_value(true), do: "true"
  defp format_output_value(false), do: "false"

  defp format_output_value(value) when is_list(value) do
    # For arrays, join with commas
    Enum.map_join(value, ", ", &format_output_value/1)
  end

  defp format_output_value(value) when is_map(value) do
    # For maps, use inspect for debugging (could be customized)
    inspect(value)
  end

  defp format_output_value(value) do
    # Fallback to inspect for other types
    inspect(value)
  end
end
