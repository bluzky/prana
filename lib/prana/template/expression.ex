defmodule Prana.Template.Expression do
  @moduledoc """
  Expression engine for extracting data from workflow context using simple path expressions.

  The Prana Expression Engine provides a simple, consistent syntax for accessing
  data in workflow executions. It supports field access, array operations,
  filtering, and wildcards with predictable output types.

  ## Syntax Overview

  All expressions start with `$` followed by a dot-separated path:

  ### Simple Field Access
  - `$input.email` - Single field from input
  - `$nodes.api_call.response.user_id` - Nested field from node output
  - `$variables.api_url` - Variable value

  ### Bracket Key Access  
  - `$input["email"]` - String key access with double quotes
  - `$input['email']` - String key access with single quotes
  - `$input[:email]` - Atom key access
  - `$input.user["0"]` - String number key (different from integer 0)
  - `$input.object[0]` - Integer key or array index

  ### Array Access
  - `$input.users[0]` - First item in array
  - `$input.users[0].name` - Field from indexed item
  - `$input.users[1][:email]` - Mixed bracket and atom access



  ## Output Behavior

  - **Simple paths**: Return single values (string, number, boolean, object)
  - **Non-expressions**: Returned as-is without processing

  ## Error Handling

  - Missing paths in simple expressions: `{:ok, nil}` (graceful handling)
  - Invalid expressions: Various error messages

  ## Quick Reference

  | Expression Type | Syntax | Output Type | Example |
  |-----------------|--------|-------------|---------|
  | **Simple Field** | `$root.field` | Single value | `$input.email` → `"john@test.com"` |
  | **Nested Field** | `$root.field.nested` | Single value | `$nodes.api.response.id` → `123` |
  | **Array Index** | `$root.array[0]` | Single value | `$input.users[0].name` → `"John"` |
  | **Static Value** | `"text"`, `123`, etc. | Unchanged | `"hello"` → `"hello"` |

  ## Context Structure

  The context is a simple map that can contain any keys. Common workflow keys:
  - `"input"` - Input data for current execution
  - `"nodes"` - Outputs from completed nodes
  - `"variables"` - Workflow variables
  """

  @doc """
  Extract value from context using expression path.

  This is the main function for expression evaluation. It automatically detects
  the expression type and returns the appropriate format:

  - **Simple expressions**: Return single values
  - **Wildcard expressions**: Return arrays of all matching values
  - **Filter expressions**: Return arrays of all matching items
  - **Non-expressions**: Return the value as-is

  ## Parameters

  - `expression` - String expression starting with `$` or any non-expression value
  - `context` - Map containing `"input"`, `"nodes"`, and `"variables"` keys

  ## Returns

  - `{:ok, value}` - Successfully extracted value (single or array), or `nil` for missing paths
  - `{:error, message}` - Invalid expression syntax or other extraction error
  """
  @spec extract(String.t(), map()) :: {:ok, any()} | {:error, String.t()}
  def extract(expression, context) when is_binary(expression) do
    if is_expression?(expression) do
      path = parse_path(expression)
      evaluate_path(path, context)
    else
      {:ok, expression}
    end
  end

  # Non-string values as-is
  def extract(value, _context), do: {:ok, value}

  @doc """
  Process a map recursively, extracting values for all expressions found.

  This function walks through maps, lists, and nested structures, processing
  any expression strings it encounters. Non-expression values are left unchanged.
  The function maintains the original structure while replacing expressions
  with their extracted values.

  ## Parameters

  - `data` - Map, list, or any value to process
  - `context` - Expression evaluation context

  ## Returns

  - `{:ok, processed_data}` - Successfully processed structure
  - `{:error, message}` - Error processing any expression
  """
  @spec process_map(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def process_map(data, context) when is_map(data) do
    process_structure(data, context, &extract/2)
  end

  def process_map(data, _context), do: {:ok, data}

  # Private functions

  defp is_expression?(value) when is_binary(value) do
    String.starts_with?(value, "$") and String.length(value) > 1
  end

  defp is_expression?(_), do: false

  # Path parsing functions

  @doc false
  def parse_path(expression) do
    expression
    |> String.split(".")
    |> Enum.flat_map(&parse_path_segment/1)
    |> validate_path()
  end

  defp parse_path_segment(segment) do
    cond do
      segment == "" ->
        # Skip empty segments from leading dots
        []

      String.contains?(segment, "[") and String.contains?(segment, "]") ->
        parse_array_segment(segment)

      String.match?(segment, ~r/^\d+$/) ->
        [String.to_integer(segment)]

      true ->
        [segment]
    end
  end

  defp parse_array_segment(segment) do
    # Parse "users[0]", "[0]", "users[\"key\"]", "users[:atom]"
    case String.split(segment, "[", parts: 2) do
      [base, index_part] ->
        index_string = String.trim_trailing(index_part, "]")
        key = parse_bracket_key(index_string)

        if base == "" do
          [key]
        else
          [base, key]
        end

      [segment] ->
        [segment]
    end
  end

  defp parse_bracket_key(key_string) do
    cond do
      # Atom key: [:email] -> :email
      String.starts_with?(key_string, ":") ->
        key_string |> String.slice(1..-1//1) |> String.to_atom()

      # Double-quoted string: ["email"] -> "email"
      String.starts_with?(key_string, "\"") and String.ends_with?(key_string, "\"") ->
        String.slice(key_string, 1..-2//1)

      # Single-quoted string: ['email'] -> "email" 
      String.starts_with?(key_string, "'") and String.ends_with?(key_string, "'") ->
        String.slice(key_string, 1..-2//1)

      # Integer: [0] -> 0
      String.match?(key_string, ~r/^\d+$/) ->
        String.to_integer(key_string)

      # Unquoted string: [email] -> "email" (fallback)
      true ->
        key_string
    end
  end

  defp validate_path(path) do
    case path do
      [] -> raise "Invalid expression: empty path"
      _ -> path
    end
  end

  # Path evaluation functions

  @doc false
  def evaluate_path(path, context) do
    # Returns single value for paths, nil if not found
    case Nested.fetch(context, path) do
      {:ok, value} -> {:ok, value}
      # Return nil instead of error for missing paths
      :error -> {:ok, nil}
    end
  end

  @doc false
  def process_structure(data, context, extract_fn) when is_map(data) do
    processed =
      Enum.reduce(data, %{}, fn {key, value}, acc ->
        case process_structure(value, context, extract_fn) do
          {:ok, processed_value} -> Map.put(acc, key, processed_value)
          {:error, reason} -> throw({:error, "Error processing key '#{key}': #{reason}"})
        end
      end)

    {:ok, processed}
  catch
    {:error, reason} -> {:error, reason}
  end

  def process_structure(data, context, extract_fn) when is_list(data) do
    processed =
      Enum.map(data, fn item ->
        case process_structure(item, context, extract_fn) do
          {:ok, processed_item} -> processed_item
          {:error, reason} -> throw({:error, reason})
        end
      end)

    {:ok, processed}
  catch
    {:error, reason} -> {:error, reason}
  end

  def process_structure(value, context, extract_fn) do
    extract_fn.(value, context)
  end
end
