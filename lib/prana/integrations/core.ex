defmodule Prana.Integrations.Core do
  @moduledoc """
  Core Integration - Essential control flow and loop constructs

  Provides fundamental workflow control actions including:
  - Loop constructs (for_each)
  - Core control flow operations
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.Integrations.Core.ForEachAction

  @impl true
  def definition do
    %Integration{
      name: "core",
      display_name: "Core",
      description: "Core control flow and loop constructs",
      version: "1.0.0",
      category: "core",
      actions: [
        ForEachAction
      ]
    }
  end
end
