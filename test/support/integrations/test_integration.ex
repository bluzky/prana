defmodule Prana.TestSupport.Integrations.TestIntegration do
  @moduledoc """
  Test Integration - Actions used only for testing purposes

  This integration contains actions that are used exclusively in tests
  to verify workflow execution, node behavior, and integration patterns.
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.TestSupport.Integrations.TestActions.SimpleAction
  alias Prana.TestSupport.Integrations.TestActions.ProcessAdultAction
  alias Prana.TestSupport.Integrations.TestActions.ProcessMinorAction
  alias Prana.TestSupport.Integrations.TestActions.TriggerAction

  @impl true
  def definition do
    %Integration{
      name: "test",
      display_name: "Test Integration",
      description: "Test actions for testing workflows",
      version: "1.0.0",
      category: "test",
      actions: [
        SimpleAction,
        ProcessAdultAction,
        ProcessMinorAction,
        TriggerAction
      ]
    }
  end
end