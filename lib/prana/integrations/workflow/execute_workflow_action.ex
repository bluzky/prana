defmodule Prana.Integrations.Workflow.ExecuteWorkflowAction do
  @moduledoc """
  Execute Sub-workflow Action - trigger a sub-workflow with coordination

  Expected params:
  - workflow_id: The ID of the sub-workflow to execute
  - input_data: Data to pass to the sub-workflow (optional, defaults to full input)
  - execution_mode: Execution mode - "sync" | "async" | "fire_and_forget" (optional, defaults to "sync")
  - timeout_ms: Maximum time to wait for sub-workflow completion in milliseconds (optional, defaults to 5 minutes)
  - failure_strategy: How to handle sub-workflow failures - "fail_parent" | "continue" (optional, defaults to "fail_parent")

  Execution Modes:
  - Synchronous ("sync"): Parent workflow suspends until sub-workflow completes
  - Asynchronous ("async"): Parent workflow suspends, sub-workflow executes async, parent resumes when complete
  - Fire-and-Forget ("fire_and_forget"): Parent workflow triggers sub-workflow and continues immediately

  Returns:
  - {:suspend, :sub_workflow_sync, suspend_data} for synchronous execution
  - {:suspend, :sub_workflow_async, suspend_data} for asynchronous execution
  - {:suspend, :sub_workflow_fire_forget, suspend_data} for fire-and-forget execution
  - {:error, reason} if sub-workflow setup fails
  """

  @behaviour Prana.Behaviour.Action

  alias Prana.Action
  alias Prana.Core.Error

  def specification do
    %Action{
      name: "execute_workflow",
      display_name: "Execute Sub-workflow",
      description: "Execute a sub-workflow with synchronous or asynchronous coordination",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main", "error", "failure", "timeout"]
    }
  end

  @impl true
  def prepare(_node) do
    {:ok, %{}}
  end

  @impl true
  def execute(params, _context) do
    # Extract configuration
    workflow_id = Map.get(params, "workflow_id")
    execution_mode = Map.get(params, "execution_mode", "sync")
    # 5 minutes default
    timeout_ms = Map.get(params, "timeout_ms", 300_000)
    failure_strategy = Map.get(params, "failure_strategy", "fail_parent")

    # Validate required parameters
    with :ok <- validate_workflow_id(workflow_id),
         :ok <- validate_execution_mode(execution_mode),
         :ok <- validate_timeout(timeout_ms),
         :ok <- validate_failure_strategy(failure_strategy) do
      # Prepare sub-workflow execution data
      sub_workflow_data = %{
        workflow_id: workflow_id,
        execution_mode: execution_mode,
        timeout_ms: timeout_ms,
        failure_strategy: failure_strategy,
        triggered_at: DateTime.utc_now()
      }

      case execution_mode do
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
    else
      {:error, reason} ->
        {:error, Error.new("action_error", reason), "error"}
    end
  end

  @impl true
  def resume(params, _context, resume_data) do
    # Extract sub-workflow execution results
    execution_mode = Map.get(params, "execution_mode", "sync")
    failure_strategy = Map.get(params, "failure_strategy", "fail_parent")

    # Process sub-workflow completion data
    case resume_data do
      %{"sub_workflow_output" => output, "status" => "completed"} ->
        # Sub-workflow completed successfully
        {:ok, output, "main"}

      %{"sub_workflow_output" => output} ->
        # Sub-workflow completed successfully (no explicit status)
        {:ok, output, "main"}

      %{"status" => "failed", "error" => error} when failure_strategy == "fail_parent" ->
        # Sub-workflow failed and should fail parent
        {:error, Error.new("action_error", "Sub-workflow failed", %{sub_workflow_error: error}), "error"}

      %{"status" => "failed", "error" => error} when failure_strategy == "continue" ->
        # Sub-workflow failed but parent should continue
        {:ok, %{sub_workflow_failed: true, error: error}, "failure"}

      %{"status" => "timeout"} when failure_strategy == "fail_parent" ->
        # Sub-workflow timed out and should fail parent
        {:error, Error.new("action_error", "Sub-workflow execution timed out"), "error"}

      %{"status" => "timeout"} when failure_strategy == "continue" ->
        # Sub-workflow timed out but parent should continue
        {:ok, %{sub_workflow_timeout: true}, "timeout"}

      # For fire-and-forget, any resume data indicates successful trigger
      _ when execution_mode == "fire_and_forget" ->
        {:ok, resume_data, "main"}

      # Default case - treat as successful completion
      _ ->
        {:ok, resume_data, "main"}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Validate workflow_id parameter
  defp validate_workflow_id(nil), do: {:error, "workflow_id is required"}
  defp validate_workflow_id(""), do: {:error, "workflow_id cannot be empty"}
  defp validate_workflow_id(workflow_id) when is_binary(workflow_id), do: :ok
  defp validate_workflow_id(_), do: {:error, "workflow_id must be a string"}

  # Validate timeout_ms parameter
  defp validate_timeout(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0, do: :ok
  defp validate_timeout(_), do: {:error, "timeout_ms must be a positive integer"}

  # Validate execution_mode parameter
  defp validate_execution_mode(mode) when mode in ["sync", "async", "fire_and_forget"], do: :ok
  defp validate_execution_mode(_), do: {:error, "execution_mode must be 'sync', 'async', or 'fire_and_forget'"}

  # Validate failure_strategy parameter
  defp validate_failure_strategy(strategy) when strategy in ["fail_parent", "continue"], do: :ok
  defp validate_failure_strategy(_), do: {:error, "failure_strategy must be 'fail_parent' or 'continue'"}
end
