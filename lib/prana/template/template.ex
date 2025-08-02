defmodule Prana.Template do
  @moduledoc """
  High-performance template engine with clean architecture and consistent error handling.

  This module provides the main public API for template processing while delegating
  to specialized modules for parsing, evaluation, and security validation.

  Key features:
  - Fast NimbleParsec-based template parsing
  - Secure evaluation with configurable limits
  - Consistent error handling across all operations
  - Clear separation of concerns in internal architecture

  ## Public API
  - `compile/1`, `compile/2`: Compile templates into AST for efficient reuse
  - `render/3`: Render string templates or compiled templates with context and optional options
  - `process_map/2`: Recursively process maps containing template expressions

  ## Template Types
  - Single expression templates return original value types
  - Mixed content templates return concatenated strings
  """

  alias Prana.Template.CompiledTemplate
  alias Prana.Template.ErrorHandler
  alias Prana.Template.Evaluator
  alias Prana.Template.Parser
  alias Prana.Template.SecurityValidator

  @doc """
  Compile a template string into an AST for efficient reuse.

  This function pre-parses and validates a template string, returning a compiled
  template that can be rendered multiple times with different contexts without
  re-parsing the template.

  ## Parameters
  - `template_string` - Template string to compile
  - `opts` - Keyword list of options (same as render/3)

  ## Returns
  - `{:ok, %CompiledTemplate{}}` - Successfully compiled template
  - `{:error, reason}` - Compilation failed

  ## Examples
      {:ok, compiled} = compile("Hello {{$input.name}}")
      {:ok, "Hello John"} = render(compiled, %{"$input" => %{"name" => "John"}})
  """
  @spec compile(String.t(), keyword()) :: {:ok, CompiledTemplate.t()} | {:error, String.t()}
  def compile(template_string, opts \\ []) when is_binary(template_string) do
    options = build_options(opts)

    with :ok <- SecurityValidator.validate_template_size(template_string, options),
         {:ok, ast} <- parse_template_safely(template_string, options) do
      compiled = CompiledTemplate.new(ast, options)
      {:ok, compiled}
    end
  end

  @doc """
  Render a template with the given context and optional options.

  This function supports both string templates and compiled templates through pattern matching.

  ## Parameters
  - `template` - Template string or compiled template from compile/2
  - `context` - Map containing variables for template evaluation
  - `opts` - Keyword list of options (optional, defaults to [])

  ## Options
  - `:strict_mode` - If true, return errors instead of fallback values (default: false)
  - `:max_template_size` - Maximum template size in bytes (default: 100,000)
  - `:max_nesting_depth` - Maximum control structure nesting (default: 50)
  - Other security options supported by SecurityValidator

  ## Examples
      # String template without options
      {:ok, "Hello John"} = render("Hello {{$input.name}}", %{"$input" => %{"name" => "John"}})

      # String template with options
      {:ok, "Hello John"} = render("Hello {{$input.name}}", %{"$input" => %{"name" => "John"}}, strict_mode: true)

      # Compiled template without options
      {:ok, compiled} = compile("Hello {{$input.name}}")
      {:ok, "Hello John"} = render(compiled, %{"$input" => %{"name" => "John"}})

      # Compiled template with options (options are ignored for compiled templates)
      {:ok, "Hello John"} = render(compiled, %{"$input" => %{"name" => "John"}}, strict_mode: true)
  """
  @spec render(String.t() | CompiledTemplate.t(), map(), keyword()) :: {:ok, String.t() | any()} | {:error, String.t()}
  def render(template, context, opts \\ [])

  def render(template_string, context, opts) when is_binary(template_string) and is_map(context) do
    options = build_options(opts)

    with :ok <- SecurityValidator.validate_template_size(template_string, options),
         {:ok, ast} <- parse_template_safely(template_string, options),
         {:ok, result} <- evaluate_template_safely(ast, context, options) do
      {:ok, result}
    else
      {:error, reason} -> ErrorHandler.apply_graceful_mode({:error, reason}, template_string, options)
    end
  end

  def render(%CompiledTemplate{ast: ast}, context, _opts) when is_map(context) do
    # For compiled templates, options are already baked in, so we ignore the opts parameter
    case Evaluator.evaluate_template(ast, context) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
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
    result = do_process_map(input_map, context, %{})
    {:ok, result}
  rescue
    error ->
      ErrorHandler.handle_evaluation_error(error)
  catch
    {:error, message} -> {:error, message}
  end

  # Private functions

  # Convert keyword list options to map with defaults
  defp build_options(opts) when is_list(opts) do
    defaults = %{
      strict_mode: false,
      # 100KB limit
      max_template_size: 100_000,
      # Maximum nesting depth for control structures
      max_nesting_depth: 50,
      # Maximum loop iterations
      max_loop_iterations: 10_000
    }

    Enum.reduce(opts, defaults, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  defp parse_template_safely(template_string, _opts) do
    case Parser.parse(template_string) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> ErrorHandler.handle_parse_error(reason)
    end
  end

  defp evaluate_template_safely(ast, context, _opts) do
    case Evaluator.evaluate_template(ast, context) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> ErrorHandler.handle_evaluation_error(reason)
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

  defp do_process_map(value, context, _opts) when is_binary(value) do
    # Check if it's a template expression
    if String.match?(value, ~r/\{\{.*\}\}/) do
      case render(value, context, []) do
        {:ok, result} -> result
        # Return original value on error in graceful mode
        {:error, _reason} -> value
      end
    else
      value
    end
  end

  defp do_process_map(value, _context, _opts), do: value
end
