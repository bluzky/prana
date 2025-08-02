defmodule Prana.Template.TemplateProcessor do
  @moduledoc """
  Core template processing logic coordinating parsing, evaluation, and security validation.

  This module orchestrates the template processing pipeline while maintaining
  separation of concerns between parsing, evaluation, and security validation.
  """

  alias Prana.Template.Parser
  alias Prana.Template.Evaluator
  alias Prana.Template.SecurityValidator
  alias Prana.Template.ErrorHandler

  @doc """
  Process a template string with the given context and options.

  This is the main processing pipeline that:
  1. Validates security constraints
  2. Parses template to AST
  3. Evaluates AST to produce result
  4. Handles errors gracefully based on options

  ## Options
  - `:strict_mode` - If true, returns errors instead of fallback values (default: false)
  - `:max_template_size` - Maximum template size in bytes (default: 100,000)
  - `:max_nesting_depth` - Maximum control structure nesting (default: 50)
  - Other security limits supported by SecurityValidator

  ## Returns
  - `{:ok, result}` - Successfully processed template
  - `{:error, reason}` - Processing failed
  """
  @spec process_template(String.t(), map(), map()) :: {:ok, String.t() | any()} | {:error, String.t()}
  def process_template(template_string, context, opts \\ %{}) when is_binary(template_string) do
    with :ok <- SecurityValidator.validate_template_size(template_string, opts),
         {:ok, ast} <- parse_template_safely(template_string, opts),
         {:ok, result} <- evaluate_template_safely(ast, context, opts) do
      {:ok, result}
    else
      {:error, reason} -> handle_processing_error(reason, template_string, opts)
    end
  end

  @doc """
  Process a map recursively, evaluating any template expressions found.

  Uses the existing Expression.process_map/2 functionality but adds
  consistent error handling through the template processor pipeline.
  """
  @spec process_map(map(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def process_map(input_map, context, opts \\ %{}) when is_map(input_map) do
    try do
      result = do_process_map(input_map, context, opts)
      {:ok, result}
    rescue
      error -> 
        ErrorHandler.handle_evaluation_error(error, opts)
    catch
      {:error, message} -> {:error, message}
    end
  end

  # Private functions

  defp parse_template_safely(template_string, opts) do
    case Parser.parse(template_string) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> ErrorHandler.handle_parse_error(reason, opts)
    end
  end

  defp evaluate_template_safely(ast, context, opts) do
    case Evaluator.evaluate_template(ast, context) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> ErrorHandler.handle_evaluation_error(reason, opts)
    end
  end

  defp handle_processing_error(reason, original_template, opts) do
    case ErrorHandler.apply_graceful_mode({:error, reason}, original_template, opts) do
      {:ok, fallback} -> {:ok, fallback}
      {:error, message} -> {:error, message}
    end
  end

  # Recursive map processing with consistent error handling
  defp do_process_map(value, context, opts) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, val}, acc ->
      processed_value = do_process_map(val, context, opts)
      Map.put(acc, key, processed_value)
    end)
  end

  defp do_process_map(value, context, opts) when is_list(value) do
    Enum.map(value, &do_process_map(&1, context, opts))
  end

  defp do_process_map(value, context, opts) when is_binary(value) do
    # Check if it's a template expression
    if String.match?(value, ~r/\{\{.*\}\}/) do
      case process_template(value, context, opts) do
        {:ok, result} -> result
        {:error, _reason} -> value  # Return original value on error in graceful mode
      end
    else
      value
    end
  end

  defp do_process_map(value, _context, _opts), do: value
end