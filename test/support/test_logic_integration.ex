defmodule Prana.TestSupport.TestLogicIntegration do
  @moduledoc """
  Test-specific Logic Integration for conditional branching tests
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Action
  alias Prana.Integration

  @impl true
  def definition do
    %Integration{
      name: "logic",
      display_name: "Test Logic",
      description: "Test logic operations for conditional branching",
      version: "1.0.0",
      category: "test",
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

  def switch(input_map) do
    switch_expression = Map.get(input_map, "switch_expression")
    cases = Map.get(input_map, "cases", %{})
    default_data = Map.get(input_map, "default_data", input_map)
    
    if switch_expression do
      case extract_value(switch_expression, input_map) do
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

  # Private helper functions
  defp evaluate_condition(condition, context) when is_binary(condition) do
    case condition do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> evaluate_simple_condition(condition, context)
    end
  end

  defp evaluate_condition(condition, _context) when is_boolean(condition) do
    {:ok, condition}
  end

  defp evaluate_condition(_condition, _context) do
    {:error, "Invalid condition type"}
  end

  defp evaluate_simple_condition(condition, context) do
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

  defp extract_value(expr, context) do
    cond do
      Regex.match?(~r/^\d+$/, expr) ->
        {value, _} = Integer.parse(expr)
        {:ok, value}
      Regex.match?(~r/^\d+\.\d+$/, expr) ->
        {value, _} = Float.parse(expr)
        {:ok, value}
      String.starts_with?(expr, "\"") and String.ends_with?(expr, "\"") ->
        value = String.slice(expr, 1..-2)
        {:ok, value}
      true ->
        case Map.get(context, expr) do
          nil -> {:error, "Field #{expr} not found"}
          value -> {:ok, value}
        end
    end
  end

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

  defp find_matching_case(switch_value, cases) do
    case_entry = Enum.find(cases, fn {case_value, _case_config} ->
      case_value == switch_value or to_string(case_value) == to_string(switch_value)
    end)
    
    case case_entry do
      {_case_value, {port_name, case_data}} ->
        {:ok, {port_name, case_data}}
      {_case_value, case_data} when is_map(case_data) ->
        case_port = determine_case_port(switch_value)
        {:ok, {case_port, case_data}}
      nil ->
        :no_match
    end
  end

  defp determine_case_port(case_value) do
    case case_value do
      "premium" -> "premium"
      "standard" -> "standard" 
      "basic" -> "basic"
      1 -> "premium"
      2 -> "standard"
      3 -> "basic"
      _ -> "default"
    end
  end
end
