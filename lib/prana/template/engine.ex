defmodule Prana.Template.Engine do
  @moduledoc """
  High-performance template engine with clean architecture and consistent error handling.

  This module provides the main public API for template processing while delegating
  to specialized modules for parsing, evaluation, and security validation.

  Key features:
  - Fast NimbleParsec-based template parsing
  - Secure evaluation with configurable limits
  - Consistent error handling across all operations
  - Graceful degradation for backward compatibility
  - Clear separation of concerns in internal architecture

  ## Public API
  - `render/2`, `render/3`: Render templates with context and options
  - `process_map/2`: Recursively process maps containing template expressions

  ## Template Types
  - Single expression templates return original value types
  - Mixed content templates return concatenated strings
  """

  alias Prana.Template.TemplateProcessor

  @doc """
  Render a template string with the given context.

  ## Parameters
  - `template_string` - Template string to render
  - `context` - Map containing variables for template evaluation

  ## Examples
      {:ok, "Hello John"} = render("Hello {{$input.name}}", %{"input" => %{"name" => "John"}})
  """
  @spec render(String.t(), map()) :: {:ok, String.t() | any()} | {:error, String.t()}
  def render(template_string, context) when is_binary(template_string) and is_map(context) do
    render(template_string, context, [])
  end

  @doc """
  Render a template string with the given context and options.

  ## Parameters
  - `template_string` - Template string to render
  - `context` - Map containing variables for template evaluation
  - `opts` - Keyword list of options

  ## Options
  - `:strict_mode` - If true, return errors instead of fallback values (default: false)
  - `:max_template_size` - Maximum template size in bytes (default: 100,000)
  - `:max_nesting_depth` - Maximum control structure nesting (default: 50)
  - Other security options supported by SecurityValidator

  ## Examples
      {:ok, "Hello John"} = render("Hello {{$input.name}}", %{"input" => %{"name" => "John"}}, strict_mode: true)
  """
  @spec render(String.t(), map(), keyword()) :: {:ok, String.t() | any()} | {:error, String.t()}
  def render(template_string, context, opts) when is_binary(template_string) and is_map(context) do
    options = build_options(opts)
    TemplateProcessor.process_template(template_string, context, options)
  end

  @doc """
  Process a map recursively, evaluating any template expressions found.

  This function walks through maps and lists, processing any template expressions
  it encounters while preserving the original structure.

  ## Parameters
  - `input_map` - Map to process
  - `context` - Map containing variables for expression evaluation

  ## Examples
      input = %{"greeting" => "Hello {{$input.name}}", "age" => 25}
      context = %{"input" => %{"name" => "John"}}
      {:ok, %{"greeting" => "Hello John", "age" => 25}} = process_map(input, context)
  """
  @spec process_map(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def process_map(input_map, context) when is_map(input_map) and is_map(context) do
    TemplateProcessor.process_map(input_map, context, %{})
  end

  # Private functions

  # Convert keyword list options to map with defaults
  defp build_options(opts) when is_list(opts) do
    defaults = %{
      strict_mode: false,  # Default to graceful mode for backward compatibility
      max_template_size: 100_000,  # 100KB limit
      max_nesting_depth: 50,       # Maximum nesting depth for control structures
      max_loop_iterations: 10_000  # Maximum loop iterations
    }
    
    Enum.reduce(opts, defaults, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end
end