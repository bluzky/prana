defmodule Prana.Integrations.Logic.IfConditionAction do
  @moduledoc """
  IF Condition Action - evaluates a condition and routes to true/false

  Expected input_map:
  - condition: expression to evaluate (e.g., "$input.age >= 18")
  - true_data: optional data to pass on true branch (defaults to input)
  - false_data: optional data to pass on false branch (defaults to input)

  Returns:
  - {:ok, data, "true"} if condition is true
  - {:ok, data, "false"} if condition is false
  - {:error, reason} if evaluation fails
  """

  @behaviour Prana.Behaviour.Action

  alias Prana.ExpressionEngine

  @impl true
  def prepare(_node) do
    {:ok, %{}}
  end

  @impl true
  def execute(input_data) do
    condition = Map.get(input_data, "condition")

    if condition do
      case evaluate_condition(condition, input_data) do
        {:ok, true} ->
          true_data = Map.get(input_data, "true_data", input_data)
          {:ok, true_data, "true"}

        {:ok, false} ->
          false_data = Map.get(input_data, "false_data", input_data)
          {:ok, false_data, "false"}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "Missing required 'condition' field"}
    end
  end

  @impl true
  def resume(_suspend_data, _resume_input) do
    {:error, "IF Condition action does not support suspension/resume"}
  end

  # Private helper function for condition evaluation
  defp evaluate_condition(condition_expr, context_data) do
    case ExpressionEngine.extract(condition_expr, context_data) do
      {:ok, result} when is_boolean(result) ->
        {:ok, result}

      {:ok, result} ->
        # Convert truthy/falsy values to boolean
        boolean_result =
          case result do
            nil -> false
            false -> false
            0 -> false
            "" -> false
            [] -> false
            %{} when map_size(result) == 0 -> false
            _ -> true
          end

        {:ok, boolean_result}
    end
  rescue
    error ->
      {:error, "Condition evaluation error: #{inspect(error)}"}
  end
end
