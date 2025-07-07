defmodule Prana.TestSupport.TestIntegration do
  @moduledoc """
  A simple test integration for testing purposes with failure simulation.
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Action
  alias Prana.Integration

  def definition do
    %Integration{
      name: "test",
      display_name: "Test Integration",
      description: "Simple test integration for unit tests",
      version: "1.0.0",
      category: "testing",
      actions: %{
        "simple_action" => %Action{
          name: "simple_action",
          display_name: "Simple Action",
          description: "A simple test action that can succeed or fail",
          type: :action,
          module: Prana.TestSupport.TestIntegration.SimpleTestAction,
          input_ports: ["input"],
          output_ports: ["success", "error"],
          default_success_port: "success",
          default_error_port: "error"
        },
        "trigger_action" => %Action{
          name: "trigger_action",
          display_name: "Test Trigger",
          description: "A simple test trigger",
          type: :trigger,
          module: Prana.TestSupport.TestIntegration.SimpleTestAction,
          input_ports: [],
          output_ports: ["success"],
          default_success_port: "success",
          default_error_port: nil
        }
      }
    }
  end
end

defmodule Prana.TestSupport.TestIntegration.SimpleTestAction do
  @moduledoc """
  Simple test action using Action behavior pattern.
  """
  
  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, _context) do
    if Map.get(params, "force_error", false) do
      # Simulate a failure
      {:error, %{
        type: "test_error",
        message: "Simulated test failure",
        details: %{input: params}
      }}
    else
      # Normal success case
      {:ok, %{
        original_input: params,
        processed: true,
        timestamp: DateTime.utc_now()
      }}
    end
  end
end