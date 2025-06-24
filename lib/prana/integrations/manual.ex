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
          module: __MODULE__,
          function: :trigger,
          input_ports: [],
          output_ports: ["success"],
          default_success_port: "success",
          default_error_port: "success"
        },
        "process_adult" => %Action{
          name: "process_adult",
          display_name: "Process Adult",
          description: "Process adult data",
          module: __MODULE__,
          function: :process_adult,
          input_ports: ["input"],
          output_ports: ["success"],
          default_success_port: "success",
          default_error_port: "success"
        },
        "process_minor" => %Action{
          name: "process_minor",
          display_name: "Process Minor",
          description: "Process minor data",
          module: __MODULE__,
          function: :process_minor,
          input_ports: ["input"],
          output_ports: ["success"],
          default_success_port: "success",
          default_error_port: "success"
        }
      }
    }
  end

  def trigger(input_map) do
    {:ok, input_map}
  end

  def process_adult(input_map) do
    result = Map.merge(input_map, %{"processed_as" => "adult", "timestamp" => DateTime.utc_now()})
    {:ok, result}
  end

  def process_minor(input_map) do
    result = Map.merge(input_map, %{"processed_as" => "minor", "timestamp" => DateTime.utc_now()})
    {:ok, result}
  end
end
