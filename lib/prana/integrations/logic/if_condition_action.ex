defmodule Prana.Integrations.Logic.IfConditionAction do
  @moduledoc """
  IF Condition Action - evaluates a condition and routes to true/false

  Expected params:
  - condition: expression to evaluate (e.g., "$input.age >= 18")

  Returns:
  - {:ok, %{}, "true"} if condition is true
  - {:ok, %{}, "false"} if condition is false
  - {:error, reason} if evaluation fails
  """

  @behaviour Prana.Behaviour.Action

  alias Prana.Action

  def specification do
    %Action{
      name: "logic.if_condition",
      display_name: "IF Condition",
      description: "Evaluate condition and route to true/false",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["true", "false"]
    }
  end

  @impl true
  def prepare(_node) do
    {:ok, %{}}
  end

  @impl true
  def execute(params, _context) do
    case Map.fetch(params, "condition") do
      {:ok, value} ->
        if value == true do
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
