defmodule Prana.Integrations.Workflow.ExecuteWorkflowAction do
  @moduledoc """
  Execute Sub-workflow Action - trigger a sub-workflow with coordination and batch processing

  Executes another workflow as a sub-workflow with configurable execution modes and batch processing.
  Supports synchronous, asynchronous, and fire-and-forget execution patterns.

  ## Parameters
  - `workflow_id` (required): The ID of the sub-workflow to execute
  - `input_data` (optional): Data to pass to sub-workflow. If not provided, uses context.$input.main
  - `execution_mode` (optional): Execution mode - "sync", "async", or "fire_and_forget" (default: "sync")
  - `batch_mode` (optional): Batch processing mode - "all" or "single" (default: "all")
  - `timeout_ms` (optional): Maximum time to wait for completion in milliseconds (default: 300000)
  - `failure_strategy` (optional): How to handle failures - "fail_parent" or "continue" (default: "fail_parent")

  ### Execution Modes
  - **Synchronous ("sync")**: Parent workflow suspends until sub-workflow completes
  - **Asynchronous ("async")**: Parent workflow suspends, sub-workflow executes async, parent resumes when complete
  - **Fire-and-Forget ("fire_and_forget")**: Parent workflow triggers sub-workflow and continues immediately

  ### Batch Processing Modes
  - **All ("all")**: Run sub-workflow once with all input data passed as-is
  - **Single ("single")**: Run sub-workflow for each item individually (non-arrays wrapped in list)

  ## Example Params JSON

  ### Synchronous Execution
  ```json
  {
    "workflow_id": "user-processing-workflow",
    "execution_mode": "sync",
    "batch_mode": "all",
    "timeout_ms": 60000,
    "failure_strategy": "fail_parent"
  }
  ```

  ### With Custom Input Data
  ```json
  {
    "workflow_id": "process-item-workflow",
    "input_data": {"user_id": 123, "action": "process"},
    "execution_mode": "async",
    "batch_mode": "single",
    "timeout_ms": 300000,
    "failure_strategy": "continue"
  }
  ```

  ## Output Ports
  - `main`: Sub-workflow completed successfully

  ## Error Handling
  - When `failure_strategy="fail_parent"`: Errors and timeouts fail the parent workflow
  - When `failure_strategy="continue"`: Errors and timeouts are logged as warnings but execution continues

  ## Behavior
  Input data can be explicitly provided via `input_data` parameter or automatically passed from
  parent workflow context ($input.main). The action suspends execution and delegates to the
  application for actual sub-workflow orchestration.
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action
  alias Prana.Core.Error

  require Logger

  def definition do
    %Action{
      name: "workflow.execute_workflow",
      display_name: "Execute Sub-workflow",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["main"],
      params_schema: %{
        workflow_id: [
          type: :string,
          description: "The ID of the sub-workflow to execute",
          required: true,
          min_length: 1
        ],
        input_data: [
          type: :any,
          description: "Data to pass to sub-workflow. If not provided, uses context.$input.main"
        ],
        execution_mode: [
          type: :string,
          description: "Execution mode - sync, async, or fire_and_forget",
          default: "sync",
          enum: ["sync", "async", "fire_and_forget"]
        ],
        batch_mode: [
          type: :string,
          description: "Batch processing mode - all or single",
          default: "all",
          enum: ["all", "single"]
        ],
        timeout_ms: [
          type: :integer,
          description: "Maximum time to wait for completion in milliseconds",
          default: 300_000,
          min: 1
        ],
        failure_strategy: [
          type: :string,
          description: "How to handle failures - fail_parent or continue",
          default: "fail_parent",
          enum: ["fail_parent", "continue"]
        ]
      }
    }
  end

  @impl true
  def execute(params, context) do
    input_data = params[:input_data] || get_in(context, ["$input", "main"])
    normalized_input = normalize_input(input_data, params.batch_mode)

    sub_workflow_data = %{
      "workflow_id" => params.workflow_id,
      "execution_mode" => params.execution_mode,
      "batch_mode" => params.batch_mode,
      "timeout_ms" => params.timeout_ms,
      "failure_strategy" => params.failure_strategy,
      "input_data" => normalized_input,
      "triggered_at" => DateTime.utc_now()
    }

    suspension_type = suspension_type_for_mode(params.execution_mode)
    {:suspend, suspension_type, sub_workflow_data}
  end

  defp normalize_input(input_data, "all"), do: input_data || %{}

  defp normalize_input(nil, "single"), do: []
  defp normalize_input(data, "single") when is_list(data), do: data
  defp normalize_input(data, "single"), do: [data]

  defp suspension_type_for_mode("sync"), do: :sub_workflow_sync
  defp suspension_type_for_mode("async"), do: :sub_workflow_async
  defp suspension_type_for_mode("fire_and_forget"), do: :sub_workflow_fire_forget

  @impl true
  def resume(params, _context, resume_data) do
    case resume_data do
      %{"output" => output, "status" => "completed"} -> {:ok, output}
      %{"output" => output} -> {:ok, output}
      %{"status" => "failed", "error" => error} -> handle_failure(error, params.failure_strategy)
      %{"status" => "timeout"} -> handle_timeout(params.failure_strategy)
      _ when params.execution_mode == "fire_and_forget" -> {:ok, nil}
      _ -> {:ok, nil}
    end
  end

  defp handle_failure(error, "fail_parent") do
    {:error, Error.action_error("sub_workflow_failed", "Sub-workflow failed", %{sub_workflow_error: error})}
  end

  defp handle_failure(error, "continue") do
    Logger.warning("Sub-workflow failed but continuing: #{inspect(error)}")
    {:ok, %{sub_workflow_failed: true, error: error}}
  end

  defp handle_timeout("fail_parent") do
    {:error, Error.action_error("sub_workflow_timeout", "Sub-workflow execution timed out")}
  end

  defp handle_timeout("continue") do
    Logger.warning("Sub-workflow timed out but continuing")
    {:ok, %{sub_workflow_timeout: true}}
  end
end
