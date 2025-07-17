defmodule Prana.Integrations.Data do
  @moduledoc """
  Data Integration - Provides data manipulation and combination operations

  Supports:
  - Merge operations for combining data from multiple paths
  - Future: Transform, filter, and other data manipulation operations
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
      name: "data",
      display_name: "Data",
      description: "Data manipulation operations for workflow data processing",
      version: "1.0.0",
      category: "core",
      actions: %{
        "merge" => %Action{
          name: "merge",
          display_name: "Merge Data",
          description: "Combine data from multiple named input ports (diamond pattern coordination)",
          type: :action,
          module: Prana.Integrations.Data.MergeAction,
          input_ports: ["input_a", "input_b"],
          output_ports: ["main", "error"]
        },
        "set_data" => %Action{
          name: "set_data",
          display_name: "Set Data",
          description: "Set data",
          type: :action,
          module: Prana.Integrations.Data.SetDataAction,
          input_ports: ["main"],
          output_ports: ["main", "error"]
        }
      }
    }
  end
end
