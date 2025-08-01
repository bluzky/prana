defmodule Prana.Integrations.Workflow.ExecuteWorkflowAction do
  @moduledoc """
  Execute Sub-workflow Action - trigger a sub-workflow with coordination and batch processing

  Expected params:
  - workflow_id: The ID of the sub-workflow to execute
  - input_data: Data to pass to the sub-workflow (optional, defaults to full input from parent workflow)
  - execution_mode: Execution mode - "sync" | "async" | "fire_and_forget" (optional, defaults to "sync")
  - batch_mode: Batch processing mode - "batch" | "single" (optional, defaults to "single")
  - timeout_ms: Maximum time to wait for sub-workflow completion in milliseconds (optional, defaults to 5 minutes)
  - failure_strategy: How to handle sub-workflow failures - "fail_parent" | "continue" (optional, defaults to "fail_parent")

  Input data from parent workflow is automatically passed to the sub-workflow trigger node.

  Execution Modes:
  - Synchronous ("sync"): Parent workflow suspends until sub-workflow completes
  - Asynchronous ("async"): Parent workflow suspends, sub-workflow executes async, parent resumes when complete
  - Fire-and-Forget ("fire_and_forget"): Parent workflow triggers sub-workflow and continues immediately

  Batch Processing Modes:
  - Batch ("batch"): Run sub-workflow once with all items from input main port (input passed as-is)
  - Single ("single"): Run sub-workflow for each item individually - non-arrays are wrapped in a list for consistent processing (default)

  The integrating application is responsible for handling the actual batch execution logic.

  Returns:
  - {:suspend, :sub_workflow_sync, suspension_data} for synchronous execution
  - {:suspend, :sub_workflow_async, suspension_data} for asynchronous execution
  - {:suspend, :sub_workflow_fire_forget, suspension_data} for fire-and-forget execution
  - {:error, reason} if sub-workflow setup fails
  """

  use Skema
  use Prana.Actions.SimpleAction

  alias Prana.Action
  alias Prana.Core.Error

  defschema ExecuteWorkflowSchema do
    field(:workflow_id, :string, required: true, length: [min: 1])
    field(:execution_mode, :string, default: "sync", in: ["sync", "async", "fire_and_forget"])
    field(:batch_mode, :string, default: "single", in: ["batch", "single"])
    field(:timeout_ms, :integer, default: 300_000, number: [min: 1])
    field(:failure_strategy, :string, default: "fail_parent", in: ["fail_parent", "continue"])
  end

  def specification do
    %Action{
      name: "workflow.execute_workflow",
      display_name: "Execute Sub-workflow",
      description: "Execute a sub-workflow with synchronous or asynchronous coordination",
      type: :action,
      module: __MODULE__,
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
        # Get input data from parent workflow
        raw_input_data = get_in(context, ["$input", "main"])
        
        # Normalize input data based on batch mode
        input_data = case validated_params.batch_mode do
          "batch" -> 
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
          workflow_id: validated_params.workflow_id,
          execution_mode: validated_params.execution_mode,
          batch_mode: validated_params.batch_mode,
          timeout_ms: validated_params.timeout_ms,
          failure_strategy: validated_params.failure_strategy,
          input_data: input_data,
          triggered_at: DateTime.utc_now()
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
            {:error, Error.action_error("sub_workflow_failed", "Sub-workflow failed", %{sub_workflow_error: error}), "error"}

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
