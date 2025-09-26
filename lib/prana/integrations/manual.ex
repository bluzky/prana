defmodule Prana.Integrations.Manual do
  @moduledoc """
  Manual Integration - Simple test actions for development and testing
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.Integrations.Manual.TriggerAction

  @impl true
  def definition do
    %Integration{
      name: "manual",
      display_name: "Manual",
      description: "Manual actions for development",
      version: "1.0.0",
      category: "manual",
      actions: [
        TriggerAction
      ]
    }
  end
end
