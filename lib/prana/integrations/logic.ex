defmodule Prana.Integrations.Logic do
  @moduledoc """
  Core Logic Integration - Provides conditional branching and logic operations
  
  Supports:
  - IF conditions with true/false routing
  - Switch statements with multiple case routing
  - Merge operations for combining data from multiple paths
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Action
  alias Prana.Integration
  alias Prana.ExpressionEngine

  @doc """
  Returns the integration definition with all available actions
  """
  @impl true
  def definition do
    %Integration{
      name: "logic",
      display_name: "Logic",
      description: "Core logic operations for conditional branching and data merging",
      version: "1.0.0",
      category: "core",
      actions: %{
        "if_condition" => %Action{
          name: "if_condition",
          display_name: "IF Condition",
          description: "Evaluate a condition and route to true or false branch",
          module: __MODULE__,
          function: :if_condition,
          input_ports: ["input"],
          output_ports: ["true", "false"],
          default_success_port: "true",
          default_error_port: "false"
        },
        "switch" => %Action{
          name: "switch",
          display_name: "Switch",
          description: "Multi-case routing based on simple condition expressions",
          module: __MODULE__,
          function: :switch,
          input_ports: ["input"],
          output_ports: ["*"],
          default_success_port: "default",
          default_error_port: "default"
        }
      }
    }
  end

  @doc """
  IF Condition action - evaluates a condition and routes to true/false
  
  Expected input_map:
  - condition: expression to evaluate (e.g., "$input.age >= 18")
  - true_data: optional data to pass on true branch (defaults to input)
  - false_data: optional data to pass on false branch (defaults to input)
  
  Returns:
  - {:ok, data, "true"} if condition is true
  - {:ok, data, "false"} if condition is false
  - {:error, reason, "false"} if evaluation fails
  """
  def if_condition(input_map) do
    condition = Map.get(input_map, "condition")
    
    if condition do
      case evaluate_condition(condition, input_map) do
        {:ok, true} ->
          true_data = Map.get(input_map, "true_data", input_map)
          {:ok, true_data, "true"}
          
        {:ok, false} ->
          false_data = Map.get(input_map, "false_data", input_map)
          {:ok, false_data, "false"}
          
        {:error, reason} ->
          {:error, %{type: "condition_evaluation_error", message: reason}, "false"}
      end
    else
      {:error, %{type: "missing_condition", message: "No condition specified"}, "false"}
    end
  end

  @doc """
  Switch action - multi-case routing based on simple conditions
  
  Expected input_map:
  - cases: array of condition objects
  - default_port: default port name (optional, defaults to "default")
  - default_data: optional default data (defaults to input_map)
  
  Example:
  %{
    "cases" => [
      %{"condition" => "$input.tier", "value" => "premium", "port" => "premium_port"},
      %{"condition" => "$input.verified", "value" => true, "port" => "verified_port"},
      %{"condition" => "$input.status", "value" => "active", "port" => "active_port", "data" => %{"priority" => "high"}}
    ],
    "default_port" => "default",
    "default_data" => %{"message" => "no match"}
  }
  
  Case objects support:
  - condition: expression to evaluate (e.g., "$input.field")
  - value: expected value to match against
  - port: output port name
  - data: optional output data (defaults to input_map)
  
  Returns:
  - {:ok, data, port_name} for matching case
  - {:ok, default_data, default_port} for no match
  """
  def switch(input_map) do
    cases = Map.get(input_map, "cases", [])
    default_port = Map.get(input_map, "default_port", "default")
    default_data = Map.get(input_map, "default_data", input_map)
    
    # Try each case in order
    case find_matching_condition_case(cases, input_map) do
      {:ok, {case_port, case_data}} ->
        {:ok, case_data, case_port}
        
      :no_match ->
        {:ok, default_data, default_port}
        
      {:error, reason} ->
        {:error, %{type: "condition_switch_error", message: reason}, default_port}
    end
  end


  # ============================================================================
  # Private Helper Functions
  # ============================================================================


  # Find first matching condition case
  defp find_matching_condition_case([], _input_map), do: :no_match
  
  defp find_matching_condition_case([case_config | remaining_cases], input_map) do
    condition_expr = Map.get(case_config, "condition")
    expected_value = Map.get(case_config, "value")
    case_port = Map.get(case_config, "port", "default")
    case_data = Map.get(case_config, "data", input_map)
    
    if condition_expr do
      case evaluate_expression(condition_expr, input_map) do
        {:ok, actual_value} ->
          if values_match?(actual_value, expected_value) do
            {:ok, {case_port, case_data}}
          else
            # Try next case
            find_matching_condition_case(remaining_cases, input_map)
          end
      end
    else
      # Skip invalid case, try next
      find_matching_condition_case(remaining_cases, input_map)
    end
  end

  # Check if actual value matches expected value
  defp values_match?(actual, expected) do
    actual == expected or to_string(actual) == to_string(expected)
  end

  # Evaluate a condition expression (simple boolean evaluation)
  defp evaluate_condition(condition, context) when is_binary(condition) do
    # Simple condition evaluation - for now just handle basic comparisons
    case condition do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ ->
        # For now, treat non-boolean strings as expressions to be evaluated
        # In a real implementation, this would use the ExpressionEngine
        evaluate_simple_condition(condition, context)
    end
  end

  defp evaluate_condition(condition, _context) when is_boolean(condition) do
    {:ok, condition}
  end

  defp evaluate_condition(_condition, _context) do
    {:error, "Invalid condition type"}
  end

  # Simple condition evaluation for basic cases
  defp evaluate_simple_condition(condition, context) do
    # Basic string-based condition evaluation
    cond do
      String.contains?(condition, ">=") ->
        evaluate_comparison(condition, ">=", context)
        
      String.contains?(condition, "<=") ->
        evaluate_comparison(condition, "<=", context)
        
      String.contains?(condition, ">") ->
        evaluate_comparison(condition, ">", context)
        
      String.contains?(condition, "<") ->
        evaluate_comparison(condition, "<", context)
        
      String.contains?(condition, "==") ->
        evaluate_comparison(condition, "==", context)
        
      String.contains?(condition, "!=") ->
        evaluate_comparison(condition, "!=", context)
        
      true ->
        {:error, "Unsupported condition format: #{condition}"}
    end
  end

  # Evaluate simple comparisons like "age >= 18"
  defp evaluate_comparison(condition, operator, context) do
    parts = String.split(condition, operator, parts: 2)
    
    case parts do
      [left_expr, right_expr] ->
        left_value = extract_value(String.trim(left_expr), context)
        right_value = extract_value(String.trim(right_expr), context)
        
        case {left_value, right_value} do
          {{:ok, left}, {:ok, right}} ->
            result = apply_comparison(left, right, operator)
            {:ok, result}
            
          {{:error, reason}, _} ->
            {:error, "Left side evaluation failed: #{reason}"}
            
          {_, {:error, reason}} ->
            {:error, "Right side evaluation failed: #{reason}"}
        end
        
      _ ->
        {:error, "Invalid comparison format"}
    end
  end

  # Extract value from expression or literal
  defp extract_value(expr, context) do
    cond do
      # Simple number
      Regex.match?(~r/^\d+$/, expr) ->
        {value, _} = Integer.parse(expr)
        {:ok, value}
        
      # Simple decimal
      Regex.match?(~r/^\d+\.\d+$/, expr) ->
        {value, _} = Float.parse(expr)
        {:ok, value}
        
      # Simple string literal
      String.starts_with?(expr, "\"") and String.ends_with?(expr, "\"") ->
        value = String.slice(expr, 1..-2//-1)
        {:ok, value}
        
      # Simple field access like "age" (assumes it's in context)
      true ->
        case Map.get(context, expr) do
          nil -> {:error, "Field #{expr} not found"}
          value -> {:ok, value}
        end
    end
  end

  # Apply comparison operator
  defp apply_comparison(left, right, operator) do
    case operator do
      ">=" -> left >= right
      "<=" -> left <= right  
      ">" -> left > right
      "<" -> left < right
      "==" -> left == right
      "!=" -> left != right
    end
  end

  # Evaluate expression using ExpressionEngine
  defp evaluate_expression(expression, context) do
    ExpressionEngine.extract(expression, context)
  end


end
