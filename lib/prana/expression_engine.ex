defmodule Prana.ExpressionEngine do
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

  ### Array Access
  - `$input.users[0]` - First item in array
  - `$input.users[0].name` - Field from indexed item

  ### Wildcard Extraction (Always Returns Arrays)
  - `$input.users.*` - All users (array of objects)
  - `$input.users.*.name` - All user names (array of strings)
  - `$input.users.*.skills.*` - All skills from all users (flattened array)

  ### Filtering (Always Returns Arrays)
  - `$input.users.{role: "admin"}` - All admin users
  - `$input.users.{is_active: true}.email` - Emails of all active users
  - `$input.orders.{status: "completed", user_id: 123}` - Orders matching all conditions

  ### Filter Value Types
  - Strings: `{role: "admin"}` or `{role: 'user'}`
  - Booleans: `{is_active: true}`, `{is_verified: false}`
  - Numbers: `{age: 25}`, `{price: 29.99}`
  - Unquoted: `{status: pending}` (treated as string)

  ## Output Behavior

  - **Simple paths**: Return single values (string, number, boolean, object)
  - **Wildcard paths**: Always return arrays (even if empty or single item)
  - **Filter paths**: Always return arrays (even if empty or single match)
  - **Non-expressions**: Returned as-is without processing

  ## Error Handling

  - Missing paths in simple expressions: `{:ok, nil}` (graceful handling)
  - No matches in filters/wildcards: `{:ok, []}` (empty array)
  - Invalid expressions: Various error messages

  ## Examples

      context = %{
        "input" => %{
          "user_id" => 123,
          "users" => [
            %{"name" => "John", "role" => "admin", "is_active" => true},
            %{"name" => "Jane", "role" => "user", "is_active" => true}
          ]
        },
        "nodes" => %{"api_call" => %{"response" => %{"status" => "success"}}},
        "variables" => %{"api_url" => "https://api.com"}
      }

      # Single values
      {:ok, 123} = extract("$input.user_id", context)
      {:ok, "success"} = extract("$nodes.api_call.response.status", context)

      # Arrays from wildcards
      {:ok, ["John", "Jane"]} = extract("$input.users.*.name", context)

      # Arrays from filters
      {:ok, ["John"]} = extract("$input.users.{role: \\"admin\\"}.name", context)
      {:ok, ["John", "Jane"]} = extract("$input.users.{is_active: true}.name", context)

      # Static values
      {:ok, "hello"} = extract("hello", context)

  ## Quick Reference

  | Expression Type | Syntax | Output Type | Example |
  |-----------------|--------|-------------|---------|
  | **Simple Field** | `$root.field` | Single value | `$input.email` → `"john@test.com"` |
  | **Nested Field** | `$root.field.nested` | Single value | `$nodes.api.response.id` → `123` |
  | **Array Index** | `$root.array[0]` | Single value | `$input.users[0].name` → `"John"` |
  | **Wildcard** | `$root.array.*` | Array | `$input.users.*.name` → `["John", "Jane"]` |
  | **Filter** | `$root.array.{key: value}` | Array | `$input.users.{role: "admin"}` → `[user1, user2]` |
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

  ## Examples

      context = %{
        "input" => %{
          "email" => "john@test.com",
          "users" => [
            %{"name" => "John", "role" => "admin"},
            %{"name" => "Jane", "role" => "user"}
          ]
        },
        "nodes" => %{"api_call" => %{"response" => %{"user_id" => 123}}},
        "variables" => %{"api_url" => "https://api.com"}
      }

      # Simple field access (single values)
      {:ok, "john@test.com"} = extract("$input.email", context)
      {:ok, 123} = extract("$nodes.api_call.response.user_id", context)
      {:ok, "https://api.com"} = extract("$variables.api_url", context)
  """
  @spec extract(String.t(), map()) :: {:ok, any()} | {:error, String.t()}
  def extract(expression, context) when is_binary(expression) do
    if is_expression?(expression) do
      # parse_and_extract now always returns {:ok, value} or {:error, reason}
      # Missing paths return {:ok, nil}
      parse_and_extract(expression, context)
    else
      # Return as-is if not an expression
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

  ## Behavior

  - **Maps**: Recursively processes all values
  - **Lists**: Recursively processes all items
  - **Expressions**: Extracts using `extract/2`
  - **Other values**: Returned unchanged

  ## Examples

      context = %{
        "input" => %{
          "user_id" => 123,
          "email" => "john@test.com",
          "users" => [
            %{"name" => "John", "role" => "admin"},
            %{"name" => "Jane", "role" => "user"}
          ]
        },
        "variables" => %{"api_url" => "https://api.com"}
      }

      # Simple map processing
      input_map = %{
        "user_id" => "$input.user_id",          # Single value
        "email" => "$input.email",             # Single value
        "all_names" => "$input.users.*.name",   # Array
        "admin_names" => "$input.users.{role: \\"admin\\"}.name",  # Array
        "static" => "hello",                   # Non-expression
        "number" => 42                         # Non-expression
      }

      {:ok, result} = process_map(input_map, context)
      # result: %{
      #   "user_id" => 123,
      #   "email" => "john@test.com",
      #   "all_names" => ["John", "Jane"],
      #   "admin_names" => ["John"],
      #   "static" => "hello",
      #   "number" => 42
      # }

      # Error handling
      error_map = %{
        "valid" => "$input.email",
        "invalid" => "$input.nonexistent.field"
      }

      {:error, "Error processing key 'invalid': Path not found: ..."} = process_map(error_map, context)
  """
  @spec process_map(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def process_map(data, context) when is_map(data) do
    processed =
      Enum.reduce(data, %{}, fn {key, value}, acc ->
        case process_value(value, context) do
          {:ok, processed_value} -> Map.put(acc, key, processed_value)
          {:error, reason} -> throw({:error, "Error processing key '#{key}': #{reason}"})
        end
      end)

    {:ok, processed}
  catch
    {:error, reason} -> {:error, reason}
  end

  def process_map(data, _context), do: {:ok, data}

  # Private functions

  defp is_expression?(value) when is_binary(value) do
    String.starts_with?(value, "$") and String.length(value) > 1
  end

  defp is_expression?(_), do: false

  defp has_wildcard?(expression) when is_binary(expression) do
    String.contains?(expression, "*")
  end

  defp has_filtering?(expression) when is_binary(expression) do
    String.contains?(expression, "{") and String.contains?(expression, "}")
  end

  defp parse_and_extract(expression, context) do
    path = parse_expression_to_path(expression)

    if has_wildcard?(expression) or has_filtering?(expression) do
      # Always returns array for wildcards/filters
      results = Nested.extract(context, path)
      {:ok, results}
    else
      # Returns single value for simple paths, nil if not found
      case Nested.fetch(context, path) do
        {:ok, value} -> {:ok, value}
        :error -> {:ok, nil}  # ← Return nil instead of error for missing paths
      end
    end
  end

  defp parse_expression_to_path(expression) do
    path =
      expression
      |> String.trim_leading("$")
      |> String.split(".")
      |> Enum.flat_map(&parse_path_segment/1)

    # Validate that we have a non-empty path
    case path do
      [] -> raise "Invalid expression: empty path"
      _ -> path
    end
  end

  defp parse_path_segment(segment) do
    cond do
      segment == "*" ->
        ["*"]

      segment == "" ->
        # Skip empty segments from leading dots
        []

      String.starts_with?(segment, "{") and String.ends_with?(segment, "}") ->
        # Handle filter syntax: .{key: value}
        parse_filter_segment(segment)

      String.contains?(segment, "[") and String.contains?(segment, "]") ->
        parse_array_segment(segment)

      String.match?(segment, ~r/^\d+$/) ->
        [String.to_integer(segment)]

      true ->
        [segment]
    end
  end

  defp parse_filter_segment(segment) do
    # Parse "{is_active: true}" syntax
    # Remove { and }
    filter_string = String.slice(segment, 1..-2//1)
    filter_map = parse_filter_conditions(filter_string)
    [filter_map]
  end

  defp parse_array_segment(segment) do
    # Parse "users[0]" or "[0]"
    case String.split(segment, "[", parts: 2) do
      [base, index_part] ->
        index_string = String.trim_trailing(index_part, "]")

        case Integer.parse(index_string) do
          {index, ""} ->
            if base != "" do
              [base, index]
            else
              [index]
            end

          _ ->
            # Invalid index, treat as regular segment
            [segment]
        end

      [segment] ->
        [segment]
    end
  end

  defp parse_filter_conditions(filter_string) do
    # Parse "is_active: true, role: 'admin'" into %{is_active: true, role: "admin"}
    filter_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, ":", parts: 2) do
        [key, value] ->
          key = key |> String.trim() |> parse_key()
          value = value |> String.trim() |> parse_filter_value()
          Map.put(acc, key, value)

        _ ->
          # Skip invalid pairs
          acc
      end
    end)
  end

  defp parse_key(key_string) do
    # Keep as string to match JSON-style data structures
    # Most workflow data will have string keys from JSON APIs
    key_string
  end

  defp parse_filter_value(value_string) do
    cond do
      # Boolean values
      value_string == "true" ->
        true

      value_string == "false" ->
        false

      # String values (quoted) - prioritize double quotes
      String.starts_with?(value_string, "\"") and String.ends_with?(value_string, "\"") ->
        String.slice(value_string, 1..-2//1)

      String.starts_with?(value_string, "'") and String.ends_with?(value_string, "'") ->
        String.slice(value_string, 1..-2//1)

      # Numeric values
      String.match?(value_string, ~r/^\d+$/) ->
        String.to_integer(value_string)

      String.match?(value_string, ~r/^\d+\.\d+$/) ->
        String.to_float(value_string)

      # Default to string
      true ->
        value_string
    end
  end

  defp process_value(value, context) when is_map(value) do
    process_map(value, context)
  end

  defp process_value(value, context) when is_list(value) do
    processed =
      Enum.map(value, fn item ->
        case process_value(item, context) do
          {:ok, processed_item} -> processed_item
          {:error, reason} -> throw({:error, reason})
        end
      end)

    {:ok, processed}
  catch
    {:error, reason} -> {:error, reason}
  end

  defp process_value(value, context) do
    extract(value, context)
  end
end
