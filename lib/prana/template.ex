defmodule Prana.Template do
  @moduledoc """
  Template engine using Mau for advanced template processing.

  This module provides a wrapper around the Mau template engine to maintain
  compatibility with the existing Prana template API while leveraging Mau's
  robust template processing capabilities.

  Key features:
  - Advanced template syntax with full conditional logic
  - Whitespace control with {{- -}} syntax
  - Nested if statements and complex control flow
  - For loops inside if statements and vice versa
  - Excellent performance for compiled template reuse

  ## Public API
  - `compile/1`, `compile/2`: Compile templates (delegates to Mau.compile/2)
  - `render/3`: Render string templates or compiled templates with context and optional options
  - `process_map/2`: Recursively process maps containing template expressions

  ## Template Types
  - Single expression templates return original value types when preserve_types is enabled
  - Mixed content templates return concatenated strings
  """

  @type compiled_template :: term()
  @type context :: map()
  @type template_options :: keyword()

  @doc """
  Compile a template string for efficient reuse.

  This function delegates to Mau.compile/2 to pre-parse and validate a template string,
  returning a compiled template that can be rendered multiple times with different
  contexts without re-parsing.

  ## Parameters
  - `template_string` - Template string to compile
  - `opts` - Keyword list of options (optional, currently ignored for Mau compatibility)

  ## Returns
  - `{:ok, compiled_template}` - Successfully compiled template
  - `{:error, reason}` - Compilation failed

  ## Examples
      {:ok, compiled} = compile("Hello {{name}}")
      {:ok, "Hello John"} = render(compiled, %{"name" => "John"})
  """
  @spec compile(String.t(), template_options()) :: {:ok, compiled_template()} | {:error, String.t()}
  def compile(template_string, opts \\ []) when is_binary(template_string) do
    case Mau.compile(template_string, opts) do
      {:ok, compiled} -> {:ok, compiled}
      {:error, %Mau.Error{message: message}} -> {:error, message}
      {:error, error} -> {:error, inspect(error)}
    end
  end

  @doc """
  Render a template with the given context and optional options.

  This function supports both string templates and compiled templates, delegating
  to Mau for the actual template processing.

  ## Parameters
  - `template` - Template string or compiled template from compile/2
  - `context` - Map containing variables for template evaluation
  - `opts` - Keyword list of options (optional, defaults to [])

  ## Options
  - `:preserve_types` - If true, single expressions return original types (default: false)
  - Other options are converted to Mau-compatible format

  ## Examples
      # String template
      {:ok, "Hello John"} = render("Hello {{name}}", %{"name" => "John"})

      # With type preservation
      {:ok, 42} = render("{{age}}", %{"age" => 42}, preserve_types: true)

      # Compiled template
      {:ok, compiled} = compile("Hello {{name}}")
      {:ok, "Hello John"} = render(compiled, %{"name" => "John"})
  """
  @spec render(String.t() | compiled_template(), context(), template_options()) ::
          {:ok, String.t() | any()} | {:error, String.t()}
  def render(template, context, opts \\ []) when is_map(context) do
    # Default to preserve_types for better compatibility with existing code
    opts = Keyword.put_new(opts, :preserve_types, true)

    case Mau.render(template, context, opts) do
      {:ok, result} -> {:ok, result}
      {:error, %Mau.Error{message: message}} -> {:error, message}
      {:error, error} -> {:error, inspect(error)}
    end
  end

  @doc """
  Process a map recursively, evaluating any template expressions found.

  This function walks through maps and lists, processing any template expressions
  it encounters while preserving the original structure. Uses Mau for template
  rendering.

  ## Parameters
  - `input_map` - Map to process
  - `context` - Map containing variables for expression evaluation

  ## Examples
      input = %{"greeting" => "Hello {{name}}", "age" => 25}
      context = %{"name" => "John"}
      {:ok, %{"greeting" => "Hello John", "age" => 25}} = process_map(input, context)
  """
  @spec process_map(map(), context(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def process_map(input_map, context, opts \\ []) when is_map(input_map) and is_map(context) do
    Mau.render_map(input_map, context, opts)
  end
end
