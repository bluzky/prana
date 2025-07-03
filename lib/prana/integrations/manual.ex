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
          module: Prana.Integrations.Manual.TriggerAction,
          function: nil,  # Not used in Action behavior pattern
          input_ports: [],
          output_ports: ["success"],
          default_success_port: "success",
          default_error_port: "success"
        },
        "process_adult" => %Action{
          name: "process_adult",
          display_name: "Process Adult",
          description: "Process adult data",
          module: Prana.Integrations.Manual.ProcessAdultAction,
          function: nil,  # Not used in Action behavior pattern
          input_ports: ["input"],
          output_ports: ["success"],
          default_success_port: "success",
          default_error_port: "success"
        },
        "process_minor" => %Action{
          name: "process_minor",
          display_name: "Process Minor",
          description: "Process minor data",
          module: Prana.Integrations.Manual.ProcessMinorAction,
          function: nil,  # Not used in Action behavior pattern
          input_ports: ["input"],
          output_ports: ["success"],
          default_success_port: "success",
          default_error_port: "success"
        }
      }
    }
  end
end
