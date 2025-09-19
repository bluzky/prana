defmodule Prana.Integrations.Logic do
  @moduledoc """
  Core Logic Integration - Provides conditional branching and logic operations

  Supports:
  - IF conditions with true/false routing
  - Switch statements with multiple case routing
  - Merge operations for combining data from multiple paths
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.Integrations.Logic.IfConditionAction
  alias Prana.Integrations.Logic.SwitchAction

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
      actions: [
        IfConditionAction,
        SwitchAction
      ]
    }
  end
end
