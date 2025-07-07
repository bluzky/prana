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

  alias Prana.Action
  alias Prana.Integration

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
      actions: %{
        "execute_workflow" => %Action{
          name: "execute_workflow",
          display_name: "Execute Sub-workflow",
          description: "Execute a sub-workflow with synchronous or asynchronous coordination",
          type: :action,
          module: Prana.Integrations.Workflow.ExecuteWorkflowAction,
          input_ports: ["input"],
          output_ports: ["success", "error", "failure", "timeout"],
          
          default_error_port: "error"
        }
      }
    }
  end

end