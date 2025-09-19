defmodule Prana.Integrations.Workflow do
  @moduledoc """
  Workflow Integration - Provides sub-workflow orchestration capabilities

  Supports:
  - Synchronous sub-workflow execution (parent waits for completion)
  - Fire-and-forget sub-workflow execution (trigger and continue)
  - Parent-child workflow coordination
  - Error propagation from sub-workflows to parent
  - Timeout handling for long-running sub-workflows

  This integration implements the unified suspension/resume mechanism
  described in ADR-003 for sub-workflow orchestration.
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.Integrations.Workflow.ExecuteWorkflowAction
  alias Prana.Integrations.Workflow.SetStateAction

  @doc """
  Returns the integration definition with all available actions
  """
  @impl true
  def definition do
    %Integration{
      name: "workflow",
      display_name: "Workflow",
      description: "Sub-workflow orchestration and coordination operations",
      version: "1.0.0",
      category: "coordination",
      actions: [
        ExecuteWorkflowAction,
        SetStateAction
      ]
    }
  end
end
