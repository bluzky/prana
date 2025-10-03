defmodule Prana.TestSupport.TestIntegration do
  @moduledoc """
  A simple test integration for testing purposes with failure simulation.
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Action
  alias Prana.Integration
  alias Prana.TestSupport.TestIntegration.FailingAction
  alias Prana.TestSupport.TestIntegration.SimpleTestAction
  alias Prana.TestSupport.TestIntegration.TriggerTestAction

  def definition do
    %Integration{
      name: "test",
      display_name: "Test Integration",
      description: "Simple test integration for unit tests",
      version: "1.0.0",
      category: "testing",
      actions: [
        SimpleTestAction,
        TriggerTestAction,
        FailingAction
      ]
    }
  end
end

defmodule Prana.TestSupport.TestIntegration.SimpleTestAction do
  @moduledoc """
  Simple test action using Action behavior pattern.
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "test.simple_action",
      display_name: "Simple Action",
      description: "A simple test action that can succeed or fail",
      type: :action,
      input_ports: ["input"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(params, _context) do
    if Map.get(params, "force_error", false) do
      # Simulate a failure
      {:error,
       %{
         type: "test_error",
         message: "Simulated test failure",
         details: %{input: params}
       }}
    else
      # Normal success case
      {:ok,
       %{
         original_input: params,
         processed: true,
         timestamp: DateTime.utc_now()
       }}
    end
  end
end

defmodule Prana.TestSupport.TestIntegration.TriggerTestAction do
  @moduledoc """
  Simple test trigger using Action behavior pattern.
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "test.trigger_action",
      display_name: "Test Trigger",
      description: "A simple test trigger",
      type: :trigger,
      input_ports: [],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(_params, _context) do
    {:ok, %{triggered: true, timestamp: DateTime.utc_now()}}
  end
end

defmodule Prana.TestSupport.TestIntegration.FailingAction do
  @moduledoc """
  Failing test action for testing on_error functionality.
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "test.failing_action",
      display_name: "Failing Action",
      description: "Action that always returns an error",
      type: :action,
      input_ports: ["input"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(_params, _context) do
    {:error, "This action always fails"}
  end
end
