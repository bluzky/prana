defmodule Prana.Integrations.Logic.SwitchAction do
  @moduledoc """
  Switch Action - Multi-case routing based on simple condition expressions

  Expected params:
  - cases: list of case objects with condition, value, port, and optional data

  Example:
  %{
    "cases" => [
      %{"condition" => "$input.tier == \"premium\"", "port" => "premium_port"},
      %{"condition" => "$input.verified == true", "port" => "verified_port"},
      %{"condition" => "$input.status == \"active\"", "port" => "active_port"},
      %{"condition" => true, "port" => "default_port"}
    ]
  }

  Case objects support:
  - condition: expression to evaluate (e.g., "$input.field == \"value\"")
  - port: output port name

  Returns:
  - {:ok, nil, port_name} for matching case
  - {:ok, nil, default_port} for no match
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, context) do
    cases = Map.get(params, "cases", [])

    # Try each case in order
    case find_matching_condition_case(cases, params, context) do
      {:ok, case_port} ->
        {:ok, nil, case_port}

      :no_match ->
        {:error, %{type: "no_matching_case", message: "No matching case found"}}
    end
  end

  # Private helper functions

  # Find first matching condition case
  defp find_matching_condition_case([], _params, _context), do: :no_match

  defp find_matching_condition_case([case_config | remaining_cases], params, context) do
    condition = Map.get(case_config, "condition")
    case_port = Map.get(case_config, "port", "default")

    if condition && condition != "" do
      {:ok, case_port}
    else
      find_matching_condition_case(remaining_cases, params, context)
    end
  end
end
