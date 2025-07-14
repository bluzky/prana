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
          type: :logic,
          module: Prana.Integrations.Logic.IfConditionAction,
          input_ports: ["input"],
          output_ports: ["true", "false"]
        },
        "switch" => %Action{
          name: "switch",
          display_name: "Switch",
          description: "Multi-case routing based on simple condition expressions",
          type: :logic,
          module: Prana.Integrations.Logic.SwitchAction,
          input_ports: ["input"],
          output_ports: ["*"]
        }
      }
    }
  end
end
