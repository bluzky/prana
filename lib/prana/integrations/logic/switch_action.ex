defmodule Prana.Integrations.Logic.SwitchAction do
  @moduledoc """
  Switch Action - Multi-case routing based on simple condition expressions
  
  Expected params:
  - cases: list of case objects with condition, value, port, and optional data
  - default_port: port to use when no cases match (defaults to "default")
  - default_data: optional default data (defaults to params)
  
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
  - data: optional output data (defaults to params)
  
  Returns:
  - {:ok, data, port_name} for matching case
  - {:ok, default_data, default_port} for no match
  """

  @behaviour Prana.Behaviour.Action

  alias Prana.ExpressionEngine

  @impl true
  def prepare(_node) do
    {:ok, %{}}
  end

  @impl true
  def execute(params) do
    cases = Map.get(params, "cases", [])
    default_port = Map.get(params, "default_port", "default")
    default_data = Map.get(params, "default_data", params)
    
    # Try each case in order
    case find_matching_condition_case(cases, params) do
      {:ok, {case_port, case_data}} ->
        {:ok, case_data, case_port}
        
      :no_match ->
        {:ok, default_data, default_port}
        
      {:error, reason} ->
        {:error, %{type: "condition_switch_error", message: reason}}
    end
  end

  @impl true
  def resume(_suspend_data, _resume_input) do
    {:error, "Switch action does not support suspension/resume"}
  end

  # Private helper functions

  # Find first matching condition case
  defp find_matching_condition_case([], _params), do: :no_match
  
  defp find_matching_condition_case([case_config | remaining_cases], params) do
    condition_expr = Map.get(case_config, "condition")
    expected_value = Map.get(case_config, "value")
    case_port = Map.get(case_config, "port", "default")
    case_data = Map.get(case_config, "data", params)
    
    if condition_expr do
      case evaluate_expression(condition_expr, params) do
        {:ok, actual_value} ->
          if values_match?(actual_value, expected_value) do
            {:ok, {case_port, case_data}}
          else
            find_matching_condition_case(remaining_cases, params)
          end
          
        {:error, reason} ->
          {:error, "Expression evaluation failed: #{inspect(reason)}"}
      end
    else
      {:error, "Missing 'condition' in case configuration"}
    end
  end

  # Evaluate expression using the expression engine
  defp evaluate_expression(expr, context_data) do
    ExpressionEngine.extract(expr, context_data)
  rescue
    error ->
      {:error, "Expression evaluation error: #{inspect(error)}"}
  end

  # Check if two values match with type coercion
  defp values_match?(actual, expected) do
    cond do
      actual === expected -> true
      is_binary(actual) and is_binary(expected) -> String.downcase(actual) == String.downcase(expected)
      is_number(actual) and is_binary(expected) -> to_string(actual) == expected
      is_binary(actual) and is_number(expected) -> actual == to_string(expected)
      is_boolean(actual) and is_binary(expected) -> to_string(actual) == String.downcase(expected)
      is_binary(actual) and is_boolean(expected) -> String.downcase(actual) == to_string(expected)
      true -> false
    end
  end
end