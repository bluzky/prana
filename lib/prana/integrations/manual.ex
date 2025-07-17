defmodule Prana.Integrations.Manual do
  @moduledoc """
  Manual Integration - Simple test actions for development and testing
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.Integrations.Manual.AttemptOperationAction
  alias Prana.Integrations.Manual.IncrementAction
  alias Prana.Integrations.Manual.IncrementRetryAction
  alias Prana.Integrations.Manual.ProcessAdultAction
  alias Prana.Integrations.Manual.ProcessMinorAction
  alias Prana.Integrations.Manual.SetDataAction
  alias Prana.Integrations.Manual.TriggerAction

  @impl true
  def definition do
    %Integration{
      name: "manual",
      display_name: "Manual",
      description: "Manual test actions for development",
      version: "1.0.0",
      category: "test",
      actions: %{
        "trigger" => TriggerAction.specification(),
        "process_adult" => ProcessAdultAction.specification(),
        "process_minor" => ProcessMinorAction.specification(),
        "set_data" => SetDataAction.specification(),
        "attempt_operation" => AttemptOperationAction.specification(),
        "increment_retry" => IncrementRetryAction.specification(),
        "increment" => IncrementAction.specification()
      }
    }
  end
end
