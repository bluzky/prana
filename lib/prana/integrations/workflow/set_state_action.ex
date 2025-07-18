defmodule Prana.Integrations.Workflow.SetStateAction do
  @moduledoc """
  Action for setting values in the workflow execution state.

  This action allows workflows to modify shared state that persists across
  node executions. All input parameters are directly merged into the execution state.

  ## Behavior

  - Takes input parameters and merges them into `$execution.state`
  - Merge semantics preserve existing state values not being updated
  - Empty output data (state is the primary side effect)

  ## Example Usage

      # Node parameters will be merged into execution state
      %{
        "counter" => 10,
        "user_data" => %{"name" => "John", "role" => "admin"},
        "session_id" => "abc123"
      }

      # These parameters become available in subsequent nodes via:
      # $execution.state.counter
      # $execution.state.user_data.name  
      # $execution.state.session_id

  ## State Merging

      # Original state: %{"counter" => 1, "email" => "test@example.com"}
      # Node parameters: %{"counter" => 10, "status" => "active"}
      # Final state: %{"counter" => 10, "email" => "test@example.com", "status" => "active"}
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "workflow.set_state",
      display_name: "Set State",
      description: "Set or update values in workflow execution state",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(params, _context) do
    {:ok, %{}, "main", params}
  end
end
