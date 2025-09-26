defmodule Prana.Integrations.Logic.IfConditionAction do
  @moduledoc """
  IF Condition Action - evaluates a condition and routes to true/false

  Evaluates a condition expression and routes workflow execution to either the "true" or "false" output port.
  Uses simple truthiness evaluation - any non-empty, non-nil value is considered true.

  ## Parameters
  - `condition` (required): Expression or value to evaluate for truthiness

  ## Example Params JSON
  ```json
  {
    "condition": "{{$input.age >= 18}}"
  }
  ```

  ## Output Ports
  - `true`: Routed when condition is truthy (non-nil, non-empty)
  - `false`: Routed when condition is falsy (nil, empty string, false)

  ## Returns
  - `{:ok, %{}, "true"}` if condition is true
  - `{:ok, %{}, "false"}` if condition is false
  - `{:error, reason}` if evaluation fails
  """

  @behaviour Prana.Behaviour.Action

  alias Prana.Action

  def definition do
    %Action{
      name: "logic.if_condition",
      display_name: "IF Condition",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["true", "false"],
      params_schema: %{
        condition: [
          type: :boolean,
          description: "Expression or value to evaluate for truthiness",
          required: true
        ]
      }
    }
  end

  @impl true
  def prepare(_node) do
    {:ok, %{}}
  end

  @impl true
  def execute(params, _context) do
    if params.condition do
      {:ok, %{}, "true"}
    else
      {:ok, %{}, "false"}
    end
  end

  @impl true
  def resume(_params, _context, _resume_data) do
    {:error, "IF Condition action does not support suspension/resume"}
  end
end
