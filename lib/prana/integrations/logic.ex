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
          description: "Multi-case routing based on expression evaluation",
          module: __MODULE__,
          function: :switch,
          input_ports: ["input"],
          output_ports: ["premium", "standard", "basic", "default"],
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
  Switch action - multi-case routing based on expression value
  
  Expected input_map:
  - switch_expression: expression to evaluate (e.g., "user_type")
  - cases: map of case_value => {port_name, output_data}
  - default_data: data for default case
  
  Example:
  %{
    "switch_expression" => "user_type",
    "cases" => %{
      "premium" => {"premium", %{"discount" => 0.2}},
      "standard" => {"standard", %{"discount" => 0.1}},
      "basic" => {"basic", %{"discount" => 0.0}}
    },
    "default_data" => %{"discount" => 0.0}
  }
  
  Returns:
  - {:ok, data, port_name} for matching case
  - {:ok, default_data, "default"} for no match
  """
  def switch(input_map) do
    switch_expression = Map.get(input_map, "switch_expression")
    cases = Map.get(input_map, "cases", %{})
    default_data = Map.get(input_map, "default_data", input_map)
    
    if switch_expression do
      case evaluate_expression(switch_expression, input_map) do
        {:ok, switch_value} ->
          case find_matching_case(switch_value, cases) do
            {:ok, {case_port, case_data}} ->
              {:ok, case_data, case_port}
              
            :no_match ->
              {:ok, default_data, "default"}
          end
          
        {:error, reason} ->
          {:error, %{type: "switch_evaluation_error", message: reason}, "default"}
      end
    else
      {:error, %{type: "missing_switch_expression", message: "No switch expression specified"}, "default"}
    end
  end


  # ============================================================================
  # Private Helper Functions
  # ============================================================================

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

  # Evaluate general expression (placeholder for now)
  defp evaluate_expression(expression, context) do
    # For now, just extract simple values
    extract_value(expression, context)
  end

  # Find matching case in switch cases
  defp find_matching_case(switch_value, cases) do
    case_entry = Enum.find(cases, fn {case_value, _case_config} ->
      case_value == switch_value or to_string(case_value) == to_string(switch_value)
    end)
    
    case case_entry do
      {_case_value, {port_name, case_data}} ->
        # New format: {port_name, case_data}
        {:ok, {port_name, case_data}}
        
      {_case_value, case_data} when is_map(case_data) ->
        # Legacy format: just case_data (auto-determine port)
        case_port = determine_case_port(switch_value)
        {:ok, {case_port, case_data}}
        
      nil ->
        :no_match
    end
  end

  # Determine which case port to use (legacy support)
  defp determine_case_port(case_value) do
    case case_value do
      "premium" -> "premium"
      "standard" -> "standard" 
      "basic" -> "basic"
      1 -> "premium"  # Backward compatibility
      2 -> "standard"
      3 -> "basic"
      _ -> "default"
    end
  end

end
