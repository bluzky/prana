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
  # Security limits
  # 1MB max template size
  @max_template_size 1_000_000
  # Max control flow nesting depth
  @max_nesting_depth 50

  @spec render(String.t(), map(), keyword()) :: {:ok, any()} | {:error, String.t()}
  def render(template_string, context, _opts \\ []) when is_binary(template_string) and is_map(context) do
    # Input validation for security
    with :ok <- validate_template_size(template_string),
         :ok <- validate_template_complexity(template_string) do
      # Extract template blocks once
      case Extractor.extract(template_string) do
        {:ok, blocks} ->
          # Check if this is a pure expression and render accordingly
          if pure_expression_blocks?(blocks) do
            render_pure_expression_from_blocks(blocks, context)
          else
            render_blocks_as_string(blocks, context)
          end

        {:error, reason} ->
          {:error, "Template extraction failed: #{reason}"}
      end
    end
  end

  def process_map(template_map, context) do
    processed =
      Enum.reduce(template_map, %{}, fn
        {key, value}, acc when is_binary(value) ->
          case render(value, context) do
            {:ok, processed_value} -> Map.put(acc, key, processed_value)
            {:error, reason} -> throw({:error, "Error processing key '#{key}': #{reason}"})
          end

        {key, value}, acc when is_map(value) ->
          case process_map(value, context) do
            {:ok, processed_value} -> Map.put(acc, key, processed_value)
            {:error, reason} -> throw({:error, "Error processing key '#{key}': #{reason}"})
          end

        {key, value}, acc when is_list(value) ->
          # Process lists by handling different item types
          processed_list =
            Enum.map(value, fn item ->
              cond do
                is_binary(item) ->
                  case render(item, context) do
                    {:ok, rendered_item} -> rendered_item
                    {:error, reason} -> throw({:error, "Error processing list item for key '#{key}': #{reason}"})
                  end

                is_map(item) ->
                  case process_map(item, context) do
                    {:ok, processed_item} -> processed_item
                    {:error, reason} -> throw({:error, "Error processing list item for key '#{key}': #{reason}"})
                  end

                true ->
                  # For other types (numbers, booleans, etc.), return as-is
                  item
              end
            end)

          Map.put(acc, key, processed_list)

        {k, v}, acc ->
          Map.put(acc, k, v)
      end)

    {:ok, processed}
  catch
    {:error, reason} -> {:error, reason}
  end

  # Private functions

  defp validate_template_size(template) do
    size = byte_size(template)

    if size > @max_template_size do
      {:error, "Template size (#{size} bytes) exceeds maximum allowed (#{@max_template_size} bytes)"}
    else
      :ok
    end
  end

  defp validate_template_complexity(template) do
    # Count control flow nesting depth
    nesting_depth = count_max_nesting_depth(template)

    if nesting_depth > @max_nesting_depth do
      {:error, "Template nesting depth (#{nesting_depth}) exceeds maximum allowed (#{@max_nesting_depth})"}
    else
      :ok
    end
  end

  defp count_max_nesting_depth(template) do
    # More accurate nesting depth counting using regex
    control_blocks = Regex.scan(~r/\{%\s*(for|if|endfor|endif)\b/, template)

    control_blocks
    |> Enum.reduce({0, 0}, fn [_full, type], {current_depth, max_depth} ->
      case type do
        type when type in ["for", "if"] ->
          new_depth = current_depth + 1
          {new_depth, max(max_depth, new_depth)}

        type when type in ["endfor", "endif"] ->
          {max(0, current_depth - 1), max_depth}

        _ ->
          {current_depth, max_depth}
      end
    end)
    |> elem(1)
  end

  defp pure_expression_blocks?(blocks) do
    # Pure expression = exactly one expression block, no literal text at all
    # Control flow blocks are not considered pure expressions
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

  defp render_single_block({:control, type, attributes, body}, context) do
    # Parse control flow block into AST and evaluate
    case ExpressionParser.parse_control_block(type, attributes, body) do
      {:ok, ast} ->
        # Evaluate the control flow AST
        case Evaluator.evaluate(ast, context) do
          {:ok, value} ->
            {:ok, format_output_value(value)}

          {:error, reason} ->
            # Log error but return the error message for security tests
            Logger.error("Control flow evaluation failed: #{reason}")
            {:ok, "Error: #{reason}"}
        end

      {:error, reason} ->
        Logger.error("Control flow parsing failed: #{reason}")
        # Return error message for parsing failures
        {:ok, "Error: #{reason}"}
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
