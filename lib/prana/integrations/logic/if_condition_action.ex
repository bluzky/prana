defmodule Prana.Integrations.Logic.IfConditionAction do
  @moduledoc """
  IF Condition Action - evaluates a condition and routes to true/false

  Expected params:
  - condition: expression to evaluate (e.g., "$input.age >= 18")
  - true_data: optional data to pass on true branch (defaults to params)
  - false_data: optional data to pass on false branch (defaults to params)

  Returns:
  - {:ok, data, "true"} if condition is true
  - {:ok, data, "false"} if condition is false
  - {:error, reason} if evaluation fails
  """

  @behaviour Prana.Behaviour.Action

  @impl true
  def prepare(_node) do
    {:ok, %{}}
  end

  @impl true
  def execute(params, _context) do
    case Map.fetch(params, "condition") do
      {:ok, value} ->
        if value && value != "" do
          {:ok, %{}, "true"}
        else
          {:ok, %{}, "false"}
        end

      _ ->
        {:error, "Missing required 'condition' field"}
    end
  end

  @impl true
  def resume(_params, _context, _resume_data) do
    {:error, "IF Condition action does not support suspension/resume"}
  end
end
