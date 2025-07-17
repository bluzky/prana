defmodule Prana.Integrations.Data do
  @moduledoc """
  Data Integration - Provides data manipulation and combination operations

  Supports:
  - Merge operations for combining data from multiple paths
  - Future: Transform, filter, and other data manipulation operations
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.Integrations.Data.MergeAction
  alias Prana.Integrations.Data.SetDataAction

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
        "merge" => MergeAction.specification(),
        "set_data" => SetDataAction.specification()
      }
    }
  end
end
