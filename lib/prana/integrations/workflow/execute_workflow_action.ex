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
  - `error`: Sub-workflow failed (when failure_strategy="fail_parent")
  - `failure`: Sub-workflow failed but continuing (when failure_strategy="continue")
  - `timeout`: Sub-workflow timed out

  ## Behavior
  Input data can be explicitly provided via `input_data` parameter or automatically passed from
  parent workflow context ($input.main). The action suspends execution and delegates to the
  application for actual sub-workflow orchestration.
  """

  use Skema
  use Prana.Actions.SimpleAction

  alias Prana.Action
  alias Prana.Core.Error

  defschema ExecuteWorkflowSchema do
    field(:workflow_id, :string, required: true, length: [min: 1])
    field(:input_data, :any)
    field(:execution_mode, :string, default: "sync", in: ["sync", "async", "fire_and_forget"])
    field(:batch_mode, :string, default: "all", in: ["all", "single"])
    field(:timeout_ms, :integer, default: 300_000, number: [min: 1])
    field(:failure_strategy, :string, default: "fail_parent", in: ["fail_parent", "continue"])
  end

  def definition do
    %Action{
      name: "workflow.execute_workflow",
      display_name: "Execute Sub-workflow",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["main", "error", "failure", "timeout"]
    }
  end

  @impl true
  def params_schema, do: ExecuteWorkflowSchema

  @impl true
  def validate_params(input_map) do
    case Skema.cast_and_validate(input_map, ExecuteWorkflowSchema) do
      {:ok, validated_data} -> {:ok, validated_data}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  @impl true
  def execute(params, context) do
    # Use Skema validation
    case validate_params(params) do
      {:ok, validated_params} ->
        # Get input data from params or fallback to context
        raw_input_data =
          case Map.get(validated_params, :input_data) do
            nil -> get_in(context, ["$input", "main"])
            data -> data
          end

        # Normalize input data based on batch mode
        input_data =
          case validated_params.batch_mode do
            "all" ->
              # Batch mode: pass input as-is, default to empty map if nil
              raw_input_data || %{}

            "single" ->
              # Single mode: wrap non-arrays in a list for consistent processing
              # Treat nil/missing input as empty list instead of wrapping nil
              case raw_input_data do
                nil -> []
                data when is_list(data) -> data
                data -> [data]
              end
          end

        sub_workflow_data = %{
          "workflow_id" => validated_params.workflow_id,
          "execution_mode" => validated_params.execution_mode,
          "batch_mode" => validated_params.batch_mode,
          "timeout_ms" => validated_params.timeout_ms,
          "failure_strategy" => validated_params.failure_strategy,
          "input_data" => input_data,
          "triggered_at" => DateTime.utc_now()
        }

        case validated_params.execution_mode do
          "sync" ->
            # Synchronous execution - suspend parent workflow (caller handles child execution and resume)
            {:suspend, :sub_workflow_sync, sub_workflow_data}

          "async" ->
            # Asynchronous execution - suspend parent workflow (caller handles async child execution and resume)
            {:suspend, :sub_workflow_async, sub_workflow_data}

          "fire_and_forget" ->
            # Fire-and-forget execution - suspend briefly (caller triggers child and immediately resumes)
            {:suspend, :sub_workflow_fire_forget, sub_workflow_data}
        end

      {:error, errors} ->
        {:error, Error.action_error("action_error", Enum.join(errors, "; ")), "error"}
    end
  end

  @impl true
  def resume(params, _context, resume_data) do
    # Use Skema validation for resume as well
    case validate_params(params) do
      {:ok, validated_params} ->
        # Extract sub-workflow execution results
        execution_mode = validated_params.execution_mode
        failure_strategy = validated_params.failure_strategy

        # Process sub-workflow completion data
        case resume_data do
          %{"output" => output, "status" => "completed"} ->
            # Sub-workflow completed successfully
            {:ok, output, "main"}

          %{"output" => output} ->
            # Sub-workflow completed successfully (no explicit status)
            {:ok, output, "main"}

          %{"status" => "failed", "error" => error} when failure_strategy == "fail_parent" ->
            # Sub-workflow failed and should fail parent
            {:error, Error.action_error("sub_workflow_failed", "Sub-workflow failed", %{sub_workflow_error: error}),
             "error"}

          %{"status" => "failed", "error" => error} when failure_strategy == "continue" ->
            # Sub-workflow failed but parent should continue
            {:ok, %{sub_workflow_failed: true, error: error}, "failure"}

          %{"status" => "timeout"} when failure_strategy == "fail_parent" ->
            # Sub-workflow timed out and should fail parent
            {:error, Error.action_error("sub_workflow_timeout", "Sub-workflow execution timed out"), "error"}

          %{"status" => "timeout"} when failure_strategy == "continue" ->
            # Sub-workflow timed out but parent should continue
            {:ok, %{sub_workflow_timeout: true}, "timeout"}

          _ when execution_mode == "fire_and_forget" ->
            {:ok, nil, "main"}

          _ ->
            {:ok, nil, "main"}
        end

      {:error, errors} ->
        {:error, Error.action_error("action_error", Enum.join(errors, "; ")), "error"}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Format validation errors
  defp format_errors(errors) do
    Enum.map(errors, fn
      {field, messages} when is_list(messages) ->
        "#{field}: #{Enum.join(messages, ", ")}"

      {field, message} when is_binary(message) ->
        "#{field}: #{message}"

      {field, message} ->
        "#{field}: #{inspect(message)}"
    end)
  end
end
