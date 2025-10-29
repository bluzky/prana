defmodule Prana.Integrations.Logic.SwitchAction do
  @moduledoc """
  Switch Action - Multi-case routing based on boolean conditions

  Evaluates multiple conditions in order and routes to the first matching case's output port.
  Only matches conditions that are exactly `true` - all other values (false, nil, strings, etc.) are considered non-matching.

  ## Parameters
  - `cases` (required): Array of case objects to evaluate in order

  Each case object contains:
  - `condition` (required): Boolean value or template expression that evaluates to true/false
  - `port` (required): Output port name to route to if condition is true

  ## Example Params JSON
  ```json
  {
    "cases": [
      {
        "condition": "{{$input.tier == 'premium'}}",
        "port": "premium_port"
      },
      {
        "condition": "{{$input.verified == true}}",
        "port": "verified_port"
      },
      {
        "condition": "{{$input.status == 'active'}}",
        "port": "active_port"
      },
      {
        "condition": true,
        "port": "default_port"
      }
    ]
  }
  ```

  ## Output Ports
  Dynamic ports based on case definitions. Common patterns:
  - Named condition ports (e.g., "premium", "standard", "basic")
  - "default" port for fallback cases

  ## Returns
  - `{:ok, nil, port_name}` for first matching case
  - `{:error, reason}` if no matching case found
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action
  alias Prana.Core.Error

  def definition do
    %Action{
      name: "logic.switch",
      display_name: "Switch",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["*"],
      params_schema: %{
        cases: [
          type:
            {:array,
             %{
               condition: [
                 type: :boolean,
                 description: "Boolean condition to evaluate",
                 required: true
               ],
               port: [
                 type: :string,
                 description: "Output port to route to if condition is true",
                 required: true
               ]
             }},
          description: "Array of case objects with condition and port",
          required: true
        ]
      }
    }
  end

  @impl true
  def execute(params, context) do
    # Check if cases parameter exists
    cases = Map.get(params, :cases)

    if cases do
      # Try each case in order
      case find_matching_condition_case(cases, context) do
        {:ok, case_port} ->
          {:ok, nil, case_port}

        :no_match ->
          {:error, Error.new("no_matching_case", "No matching case found")}
      end
    else
      {:error, Error.new("missing_cases", "Cases parameter is required")}
    end
  end

  # Private helper functions

  # Find first matching condition case
  defp find_matching_condition_case([], _context), do: :no_match

  defp find_matching_condition_case([case_config | remaining_cases], context) do
    if case_config.condition do
      {:ok, case_config.port}
    else
      find_matching_condition_case(remaining_cases, context)
    end
  end
end
