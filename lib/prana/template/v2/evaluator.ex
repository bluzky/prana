defmodule Prana.Template.V2.Evaluator do
  @moduledoc """
  AST evaluator for NimbleParsec-generated template and expression trees.
  
  Handles:
  - Template block evaluation (literals, expressions, control flow)
  - Expression evaluation with full operator precedence
  - Variable resolution using existing Expression module
  - Filter application via FilterRegistry
  - Control flow (if/else, for loops) with proper scoping
  - Security limits and error handling
  """
  
  alias Prana.Template.Expression
  alias Prana.Template.FilterRegistry
  
  # Security limits
  @max_loop_iterations 10_000
  @max_recursion_depth 100
  
  @spec evaluate_template(list(), map()) :: {:ok, String.t() | any()} | {:error, String.t()}
  def evaluate_template(ast_blocks, context) when is_list(ast_blocks) do
    case detect_single_expression(ast_blocks) do
      {:single_expression, expression_ast} ->
        # Single expression template - return original value type
        evaluate_expression(expression_ast, context)
        
      :mixed_content ->
        # Mixed content template - return concatenated string
        evaluate_template_blocks(ast_blocks, context, "")
    end
  end
  
  @spec evaluate_expression(any(), map()) :: {:ok, any()} | {:error, String.t()}
  def evaluate_expression(ast, context) do
    try do
      result = do_evaluate_expression(ast, context, 0)
      {:ok, result}
    rescue
      error -> {:error, "Expression evaluation failed: #{inspect(error)}"}
    catch
      {:error, message} -> {:error, message}
      {:max_recursion, depth} -> {:error, "Maximum recursion depth (#{@max_recursion_depth}) exceeded at depth #{depth}"}
    end
  end
  
  @spec evaluate_control_block(atom(), any(), list(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def evaluate_control_block(type, condition, body, context) do
    try do
      result = do_evaluate_control_block(type, condition, body, context, 0)
      {:ok, result}
    rescue
      error -> {:error, "Control block evaluation failed: #{inspect(error)}"}
    catch
      {:error, message} -> {:error, message}
    end
  end
  
  # Private implementation functions
  
  defp detect_single_expression(ast_blocks) do
    case ast_blocks do
      [{:expression, expression_content}] ->
        # Parse the expression content to get the AST
        case Prana.Template.V2.ExpressionParser.parse(String.trim(expression_content)) do
          {:ok, ast} -> {:single_expression, ast}
          {:error, _reason} -> :mixed_content
        end
      _ ->
        :mixed_content
    end
  end
  
  defp evaluate_template_blocks([], _context, acc), do: {:ok, acc}
  
  defp evaluate_template_blocks([block | rest], context, acc) do
    case evaluate_template_block(block, context) do
      {:ok, result} ->
        string_result = if is_binary(result), do: result, else: to_string(result || "")
        evaluate_template_blocks(rest, context, acc <> string_result)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Nesting-aware version for control structures
  defp evaluate_template_blocks_with_nesting([], _context, acc, _nesting_depth), do: {:ok, acc}
  
  defp evaluate_template_blocks_with_nesting([block | rest], context, acc, nesting_depth) do
    case evaluate_template_block_with_nesting(block, context, nesting_depth) do
      {:ok, result} ->
        string_result = if is_binary(result), do: result, else: to_string(result || "")
        evaluate_template_blocks_with_nesting(rest, context, acc <> string_result, nesting_depth)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp evaluate_template_block({:literal, text}, _context), do: {:ok, text}
  
  defp evaluate_template_block({:expression, expression_content}, context) do
    # Parse and evaluate the expression content
    case Prana.Template.V2.ExpressionParser.parse(String.trim(expression_content)) do
      {:ok, ast} ->
        evaluate_expression(ast, context)
      
      {:error, reason} ->
        {:error, "Expression parsing failed: #{reason}"}
    end
  end
  
  defp evaluate_template_block({:control, type, condition, body}, context) do
    evaluate_control_block(type, condition, body, context)
  end
  
  # Nesting-aware version for control structures
  defp evaluate_template_block_with_nesting({:literal, text}, _context, _nesting_depth), do: {:ok, text}
  
  defp evaluate_template_block_with_nesting({:expression, expression_content}, context, _nesting_depth) do
    # Parse and evaluate the expression content
    case Prana.Template.V2.ExpressionParser.parse(String.trim(expression_content)) do
      {:ok, ast} ->
        evaluate_expression(ast, context)
      
      {:error, reason} ->
        {:error, "Expression parsing failed: #{reason}"}
    end
  end
  
  defp evaluate_template_block_with_nesting({:control, type, condition, body}, context, nesting_depth) do
    # This will call do_evaluate_control_block with nesting_depth
    try do
      result = do_evaluate_control_block(type, condition, body, context, nesting_depth)
      {:ok, result}
    rescue
      error -> {:error, "Control block evaluation failed: #{inspect(error)}"}
    catch
      {:error, message} -> {:error, message}
    end
  end
  
  defp do_evaluate_expression(_ast, _context, depth) when depth > @max_recursion_depth do
    throw({:max_recursion, depth})
  end
  
  # Variable evaluation
  defp do_evaluate_expression({:variable, path}, context, _depth) do
    case Expression.extract(path, context) do
      {:ok, value} -> value
    end
  end
  
  # Local variable evaluation (for loop variables and unquoted identifiers)
  defp do_evaluate_expression({:local_variable, path}, context, _depth) do
    # Handle dotted paths like "config.currency"
    if String.contains?(path, ".") do
      path_segments = String.split(path, ".")
      get_nested_value(context, path_segments)
    else
      # Simple key access
      Map.get(context, path)
    end
  end
  
  # Unquoted identifier evaluation (same as local variable)
  defp do_evaluate_expression({:unquoted_identifier, path}, context, _depth) do
    # Handle dotted paths like "config.currency"
    if String.contains?(path, ".") do
      path_segments = String.split(path, ".")
      get_nested_value(context, path_segments)
    else
      # Simple key access
      Map.get(context, path)
    end
  end
  
  # Literal values
  defp do_evaluate_expression({:literal, value}, _context, _depth), do: value
  
  # Helper function for nested value access
  defp get_nested_value(context, []) do
    context
  end
  
  defp get_nested_value(context, [key | rest]) when is_map(context) do
    case Map.get(context, key) do
      nil -> nil
      value -> get_nested_value(value, rest)
    end
  end
  
  defp get_nested_value(_context, _path) do
    nil
  end
  
  # Binary operations
  defp do_evaluate_expression({:binary_op, op, left, right}, context, depth) do
    left_val = do_evaluate_expression(left, context, depth + 1)
    right_val = do_evaluate_expression(right, context, depth + 1)
    
    apply_binary_operation(op, left_val, right_val)
  end
  
  # Grouped expressions (parentheses)
  defp do_evaluate_expression({:grouped, inner_ast}, context, depth) do
    do_evaluate_expression(inner_ast, context, depth + 1)
  end
  
  # Function calls
  defp do_evaluate_expression({:call, function_name, args}, context, depth) when is_list(args) do
    evaluated_args = Enum.map(args, &do_evaluate_expression(&1, context, depth + 1))
    apply_function(function_name, evaluated_args)
  end
  
  defp do_evaluate_expression({:call, function_name, arg}, context, depth) do
    # Single argument case
    evaluated_arg = do_evaluate_expression(arg, context, depth + 1)
    apply_function(function_name, [evaluated_arg])
  end
  
  # Unknown AST node
  defp do_evaluate_expression(unknown_ast, _context, _depth) do
    throw({:error, "Unknown AST node: #{inspect(unknown_ast)}"})
  end
  
  # Binary operation implementation
  defp apply_binary_operation(:add, left, right) when is_number(left) and is_number(right), do: left + right
  defp apply_binary_operation(:sub, left, right) when is_number(left) and is_number(right), do: left - right
  defp apply_binary_operation(:mul, left, right) when is_number(left) and is_number(right), do: left * right
  defp apply_binary_operation(:div, left, right) when is_number(left) and is_number(right) and right != 0, do: left / right
  
  defp apply_binary_operation(:gt, left, right), do: compare_values(left, right) == :gt
  defp apply_binary_operation(:lt, left, right), do: compare_values(left, right) == :lt
  defp apply_binary_operation(:gte, left, right), do: compare_values(left, right) in [:gt, :eq]
  defp apply_binary_operation(:lte, left, right), do: compare_values(left, right) in [:lt, :eq]
  defp apply_binary_operation(:eq, left, right), do: left == right
  defp apply_binary_operation(:neq, left, right), do: left != right
  
  defp apply_binary_operation(:and, left, right), do: is_truthy(left) && is_truthy(right)
  defp apply_binary_operation(:or, left, right), do: is_truthy(left) || is_truthy(right)
  
  # Fallback for unsupported operations
  defp apply_binary_operation(op, left, right) do
    throw({:error, "Unsupported binary operation: #{op} with values #{inspect(left)} and #{inspect(right)}"})
  end
  
  # Function application (filters)
  defp apply_function(function_name, [value | filter_args]) do
    case FilterRegistry.apply_filter(function_name, value, filter_args) do
      {:ok, result} -> result
      {:error, reason} -> throw({:error, "Filter application failed: #{reason}"})
    end
  end
  
  defp apply_function(function_name, []) do
    case FilterRegistry.apply_filter(function_name, nil, []) do
      {:ok, result} -> result
      {:error, reason} -> throw({:error, "Filter application failed: #{reason}"})
    end
  end
  
  # Control flow evaluation
  defp do_evaluate_control_block(:if, condition, body, context, nesting_depth) do
    # Check nesting depth limit
    max_nesting = 50  # From default options
    if nesting_depth >= max_nesting do
      throw({:error, "Control structure nesting depth exceeds maximum allowed limit of #{max_nesting}"})
    end
    
    case Prana.Template.V2.ExpressionParser.parse(condition) do
      {:ok, condition_ast} ->
        condition_result = do_evaluate_expression(condition_ast, context, 0)
        
        if is_truthy(condition_result) do
          case evaluate_template_blocks_with_nesting(body, context, "", nesting_depth + 1) do
            {:ok, result} -> result
            {:error, reason} -> throw({:error, reason})
          end
        else
          ""
        end
      
      {:error, reason} ->
        throw({:error, "Condition parsing failed: #{reason}"})
    end
  end
  
  defp do_evaluate_control_block(:for, loop_spec, body, context, nesting_depth) do
    # Check nesting depth limit
    max_nesting = 50  # From default options
    if nesting_depth >= max_nesting do
      throw({:error, "Control structure nesting depth exceeds maximum allowed limit of #{max_nesting}"})
    end
    
    # Parse "item in collection" syntax
    case parse_for_loop_spec(loop_spec) do
      {:ok, {item_var, collection_path}} ->
        case Expression.extract(collection_path, context) do
          {:ok, collection} when is_list(collection) ->
            evaluate_for_loop_with_limits(item_var, collection, body, context, nesting_depth + 1)
          
          {:ok, _non_list} ->
            "Error: For loop iterable must be a list"
        end
      
      {:error, reason} ->
        throw({:error, reason})
    end
  end
  
  defp parse_for_loop_spec(spec) do
    case String.split(spec, " in ", parts: 2) do
      [item_var, collection_path] ->
        item_var = String.trim(item_var)
        collection_path = String.trim(collection_path)
        {:ok, {item_var, collection_path}}
      
      _ ->
        {:error, "Invalid for loop syntax: #{spec}"}
    end
  end
  
  defp evaluate_for_loop(item_var, collection, body, context) do
    collection
    |> Enum.with_index()
    |> Enum.reduce("", fn {item, index}, acc ->
      if index >= @max_loop_iterations do
        throw({:error, "Maximum loop iterations (#{@max_loop_iterations}) exceeded"})
      end
      
      # Create loop context with item variable
      loop_context = Map.put(context, "$#{item_var}", item)
      
      case evaluate_template_blocks(body, loop_context, "") do
        {:ok, result} -> acc <> result
        {:error, reason} -> throw({:error, reason})
      end
    end)
  end
  
  # Version with nesting depth tracking and graceful iteration limit handling
  defp evaluate_for_loop_with_limits(item_var, collection, body, context, nesting_depth) do
    if length(collection) > @max_loop_iterations do
      # Return error message instead of throwing for graceful handling
      "Error: For loop iterations exceeds maximum allowed limit of #{@max_loop_iterations}"
    else
      collection
      |> Enum.with_index()
      |> Enum.reduce("", fn {item, index}, acc ->
        # Create loop context with item variable (with $ prefix for structured access)
        loop_context = Map.put(context, "$#{item_var}", item)
        
        case evaluate_template_blocks_with_nesting(body, loop_context, "", nesting_depth) do
          {:ok, result} -> acc <> result
          {:error, reason} -> throw({:error, reason})
        end
      end)
    end
  end
  
  # Helper functions
  defp compare_values(left, right) do
    cond do
      left > right -> :gt
      left < right -> :lt
      left == right -> :eq
      true -> :eq  # Fallback for incomparable types
    end
  end
  
  defp is_truthy(nil), do: false
  defp is_truthy(false), do: false
  defp is_truthy(""), do: false
  defp is_truthy([]), do: false
  defp is_truthy(%{} = map) when map_size(map) == 0, do: false
  defp is_truthy(_), do: true
  
end