defmodule Prana.Integrations.Workflow.SetStateAction do
  @moduledoc """
  Action for setting values in the workflow execution state.

  This action allows workflows to modify shared state that persists across node executions.
  All input parameters are directly merged into the execution state, making them available
  to subsequent nodes via template expressions.

  ## Parameters
  Any parameters provided will be merged into the workflow execution state.
  Parameter names become state keys accessible in later nodes.

  ## Example Params JSON
  ```json
  {
    "counter": 10,
    "user_data": {
      "name": "John Doe",
      "role": "admin",
      "preferences": {
        "theme": "dark",
        "notifications": true
      }
    },
    "session_id": "abc123",
    "last_updated": "{{$execution.timestamp}}"
  }
  ```

  ## Output Ports
  - `main`: State updated successfully (returns empty object)

  ## Behavior
  - Takes input parameters and merges them into `$execution.state`
  - Merge semantics preserve existing state values not being updated
  - Empty output data (state modification is the primary side effect)

  ## State Access
  After setting state, values become available in subsequent nodes:
  ```
  {{$execution.state.counter}}              // 10
  {{$execution.state.user_data.name}}       // "John Doe"
  {{$execution.state.session_id}}           // "abc123"
  ```

  ## State Merging Example
  ```
  Original state: {"counter": 1, "email": "test@example.com"}
  Node parameters: {"counter": 10, "status": "active"}
  Final state: {"counter": 10, "email": "test@example.com", "status": "active"}
  ```
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "workflow.set_state",
      display_name: "Set State",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(params, _context) do
    {:ok, %{}, "main", params}
  end
end
