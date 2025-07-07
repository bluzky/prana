defmodule Prana.Integrations.Manual do
  @moduledoc """
  Manual Integration - Simple test actions for development and testing
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Action
  alias Prana.Integration

  @impl true
  def definition do
    %Integration{
      name: "manual",
      display_name: "Manual",
      description: "Manual test actions for development",
      version: "1.0.0",
      category: "test",
      actions: %{
        "trigger" => %Action{
          name: "trigger",
          display_name: "Manual Trigger",
          description: "Simple trigger for testing",
          type: :trigger,
          module: Prana.Integrations.Manual.TriggerAction,
          input_ports: [],
          output_ports: ["success"],
          
        
        },
        "process_adult" => %Action{
          name: "process_adult",
          display_name: "Process Adult",
          description: "Process adult data",
          type: :action,
          module: Prana.Integrations.Manual.ProcessAdultAction,
          input_ports: ["input"],
          output_ports: ["success"],
          
        
        },
        "process_minor" => %Action{
          name: "process_minor",
          display_name: "Process Minor",
          description: "Process minor data",
          type: :action,
          module: Prana.Integrations.Manual.ProcessMinorAction,
          input_ports: ["input"],
          output_ports: ["success"],
          
        
        },
        "set_data" => %Action{
          name: "set_data",
          display_name: "Set Data",
          description: "Set data for testing",
          type: :action,
          module: Prana.Integrations.Manual.SetDataAction,
          input_ports: ["input"],
          output_ports: ["success"],
          
        
        },
        "attempt_operation" => %Action{
          name: "attempt_operation",
          display_name: "Attempt Operation",
          description: "Simulate operation that may fail for retry testing",
          type: :action,
          module: Prana.Integrations.Manual.AttemptOperationAction,
          input_ports: ["input"],
          output_ports: ["success"],
          
        
        },
        "increment_retry" => %Action{
          name: "increment_retry",
          display_name: "Increment Retry",
          description: "Increment retry counter for retry testing",
          type: :action,
          module: Prana.Integrations.Manual.IncrementRetryAction,
          input_ports: ["input"],
          output_ports: ["success"],
          
        
        }
      }
    }
  end
end
