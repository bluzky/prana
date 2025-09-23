defmodule Prana.Integrations.Core.LogAction do
  @moduledoc """
  Log Action - Log execution context and input data to terminal console

  This action logs the current node key, workflow ID, execution ID, and all input data
  to the console, then passes the input data unchanged through the main output port.
  Useful for debugging workflows and monitoring data flow.

  ## Parameters
  - `message` (optional): Custom message to include in the log output
  - `level` (optional): Log level - "info", "debug", "warn", "error" (default: "info")

  ## Example Params JSON
  ```json
  {
    "message": "Processing user data",
    "level": "info"
  }
  ```

  ## Output
  Returns the input data unchanged through the "main" output port.
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "core.log",
      display_name: "Log",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(params, context) do
    input = context["$input"]["main"] || %{}

    # Get optional parameters
    message = Map.get(params, "message", "Log Action")
    level = Map.get(params, "level", "info")

    # Extract execution context
    current_node_key = get_in(context, ["$execution", "current_node_key"])
    workflow_id = get_in(context, ["$workflow", "id"])
    execution_id = get_in(context, ["$execution", "id"])

    # Log the execution context and input data
    log_output = """
    === #{message} ===
    Node: #{current_node_key} -- Workflow ID: #{workflow_id} -- Execution ID: #{execution_id}: #{inspect(input, pretty: true)}
    ==================
    """

    # Output to console based on level
    case level do
      "debug" -> IO.puts("[DEBUG] #{log_output}")
      "warn" -> IO.puts("[WARN] #{log_output}")
      "error" -> IO.puts("[ERROR] #{log_output}")
      _ -> IO.puts("[INFO] #{log_output}")
    end

    # Pass input data through unchanged
    {:ok, input}
  end
end
