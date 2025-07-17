defmodule PranaDemo.WorkflowRunner do
  @moduledoc """
  Example WorkflowRunner implementation for demonstrating Prana workflow execution.

  This module demonstrates how applications can integrate with Prana to handle
  workflow execution, suspension/resume patterns, and database persistence.
  """

  alias Prana.WorkflowExecution
  alias Prana.GraphExecutor
  alias Prana.WorkflowCompiler
  alias PranaDemo.ETSStorage

  require Logger

  @doc """
  Execute a workflow with input data and options.
  """
  def execute_workflow(workflow, input, opts \\ []) do
    Logger.info("Starting workflow execution")

    with {:ok, execution_graph} <- build_graph(workflow),
         {:ok, execution} <- init_execution(execution_graph, input, opts),
         {:ok, persisted_execution} <- insert_db(execution) do
      GraphExecutor.execute_workflow(persisted_execution)
      |> handle_result()
    else
      error ->
        Logger.error("Workflow execution failed: #{inspect(error)}")
        error
    end
  end

  @doc """
  Resume a suspended workflow with new input data.
  """
  def resume_workflow(execution, resume_input) do
    Logger.info("Resuming workflow execution: #{execution.id}")

    GraphExecutor.resume_workflow(execution, resume_input)
    |> handle_result()
  end

  # Private implementation functions

  defp build_graph(workflow) do
    Logger.debug("Building execution graph")
    WorkflowCompiler.compile(workflow)
  end

  defp init_execution(execution_graph, input, opts) do
    Logger.debug("Initializing execution context")

    # Create execution using WorkflowExecution.new
    execution = WorkflowExecution.new(execution_graph, "manual_trigger", input)

    # Rebuild runtime state with environment data
    env_data = Map.get(opts, :env, %{})
    execution_with_runtime = WorkflowExecution.rebuild_runtime(execution, env_data)

    # Add application-specific metadata
    enhanced_execution = %{
      execution_with_runtime
      | metadata:
          Map.merge(execution_with_runtime.metadata, %{
            "created_at" => DateTime.utc_now(),
            "updated_at" => DateTime.utc_now(),
            "input" => input,
            "options" => opts
          })
    }

    {:ok, enhanced_execution}
  end

  defp insert_db(execution) do
    Logger.debug("Persisting execution to ETS storage")
    ETSStorage.store_execution(execution)
  end

  defp handle_result(result) do
    case result do
      {:ok, execution} ->
        Logger.info("Workflow completed successfully")
        update_execution_db(execution, :completed)
        {:ok, execution}

      {:suspend, execution} ->
        Logger.info("Workflow suspended")

        case handle_suspend(execution) do
          {:resume, updated_execution, resume_data} ->
            Logger.info("Resuming execution immediately")
            ETSStorage.update_execution(updated_execution)

            GraphExecutor.resume_workflow(updated_execution, resume_data)
            |> handle_result()

          {:wait, updated_execution} ->
            Logger.info("Execution suspended, waiting for external trigger")
            ETSStorage.update_execution(updated_execution)
            {:ok, updated_execution}

          {:error, reason} ->
            Logger.error("Suspension handling failed: #{inspect(reason)}")
            update_execution_db(execution, :failed)
            {:error, execution}
        end

      {:error, execution} ->
        Logger.error("Workflow execution failed")
        update_execution_db(execution, :failed)
        {:error, execution}
    end
  end

  defp handle_suspend(execution) do
    case execution.suspension_type do
      # Handle wait operations (timer, scheduler, webhook, interval)
      suspend_type when suspend_type in [:timer, :scheduler, :webhook, :interval] ->
        Logger.info("Handling wait suspension: #{suspend_type}")
        handle_wait_suspension(execution)

      # Handle sub-workflow operations
      :sub_workflow ->
        Logger.info("Handling sub-workflow suspension")
        handle_sub_workflow_suspension(execution)

      :sub_workflow_sync ->
        Logger.info("Handling synchronous sub-workflow suspension")
        handle_sub_workflow_suspension(execution)

      :sub_workflow_fire_forget ->
        Logger.info("Handling fire-and-forget sub-workflow suspension")
        handle_sub_workflow_suspension(execution)

      :sub_workflow_async ->
        Logger.info("Handling asynchronous sub-workflow suspension")
        handle_sub_workflow_suspension(execution)

      nil ->
        Logger.info("No suspension type specified")
        {:wait, execution}
    end
  end

  defp handle_wait_suspension(execution) do
    Logger.info("Setting up wait operation: #{execution.suspension_type}")

    # Set up external trigger based on suspension type
    case execution.suspension_type do
      :timer ->
        schedule_timer_resume(execution)

      :interval ->
        schedule_interval_resume(execution)

      :scheduler ->
        schedule_cron_resume(execution)

      :webhook ->
        setup_webhook_listener(execution)
    end

    {:wait, execution}
  end

  defp handle_sub_workflow_suspension(execution) do
    suspension_data = execution.suspension_data
    execution_mode = suspension_data.execution_mode
    workflow_id = suspension_data.workflow_id

    Logger.info("Handling sub-workflow with mode: #{execution_mode}")
    Logger.info("Sub-workflow ID: #{workflow_id}")

    case execution_mode do
      "sync" ->
        # Execute immediately and continue
        Logger.info("Executing sub-workflow synchronously")

        # TODO: Implement synchronous sub-workflow execution
        # 1. Load sub-workflow by workflow_id from storage
        # 2. Execute sub-workflow with provided input
        # 3. Resume parent workflow with sub-workflow result
        Logger.info("TODO: Load sub-workflow #{workflow_id} and execute synchronously")
        Logger.info("TODO: Resume parent execution with sub-workflow result")
        # For now, treat as wait until implemented
        {:wait, execution}

      "async" ->
        # Enqueue for execution and suspend parent
        Logger.info("Enqueueing sub-workflow for asynchronous execution")

        # TODO: Implement asynchronous sub-workflow execution
        # 1. Enqueue sub-workflow for background execution
        # 2. Store parent execution in suspended state
        # 3. When sub-workflow completes, resume parent execution
        Logger.info("TODO: Enqueue sub-workflow #{workflow_id} for async execution")
        Logger.info("TODO: Save parent execution suspension state")
        {:wait, execution}

      "fire_and_forget" ->
        # Enqueue for execution and continue parent
        Logger.info("Enqueueing sub-workflow for fire-and-forget execution")

        # TODO: Implement fire-and-forget sub-workflow execution
        # 1. Enqueue sub-workflow for background execution
        # 2. Resume parent workflow immediately with placeholder result
        Logger.info("TODO: Enqueue sub-workflow #{workflow_id} for fire-and-forget execution")
        Logger.info("TODO: Resume parent execution immediately")
        # Fire-and-forget should resume immediately with placeholder result
        placeholder_result = %{"sub_workflow_status" => "enqueued", "workflow_id" => workflow_id}
        {:resume, execution, placeholder_result}

      _ ->
        Logger.error("Unknown execution mode: #{execution_mode}")
        {:error, "Unknown execution mode: #{execution_mode}"}
    end
  end

  # Database and external system integration helpers

  defp update_execution_db(execution, status) do
    Logger.debug("Updating execution status to: #{status}")
    updated_execution = %{execution | status: status}
    ETSStorage.update_execution(updated_execution)
    :ok
  end

  defp schedule_timer_resume(execution) do
    delay_ms = execution.suspension_data.delay_ms
    Logger.info("Scheduling timer resume in #{delay_ms}ms")

    # In a real application, use your preferred scheduling mechanism
    Process.send_after(self(), {:resume_workflow, execution, %{}}, delay_ms)
  end

  defp schedule_interval_resume(execution) do
    delay_ms = execution.suspension_data.duration_ms
    Logger.info("Scheduling interval resume in #{delay_ms}ms")

    # In a real application, use your preferred scheduling mechanism
    Process.send_after(self(), {:resume_workflow, execution, %{}}, delay_ms)
  end

  defp schedule_cron_resume(execution) do
    cron_expression = execution.suspension_data.cron_expression
    Logger.info("Scheduling cron resume: #{cron_expression}")

    # In a real application, integrate with a cron scheduler
    # This is just a placeholder
    :ok
  end

  defp setup_webhook_listener(execution) do
    webhook_url = execution.suspension_data.webhook_url
    Logger.info("Setting up webhook listener: #{webhook_url}")

    # In a real application, register webhook endpoint
    # This is just a placeholder
    :ok
  end

  defp enqueue_for_execution(_workflow, _input, _parent_execution) do
    Logger.info("Enqueueing workflow for background execution")

    # In a real application, enqueue to your job processing system
    # For example, with Oban:
    # %{workflow: workflow, input: input, parent_execution_id: parent_execution&.id}
    # |> MyApp.Workers.WorkflowExecutor.new()
    # |> Oban.insert()

    :ok
  end

  @doc """
  Start the ETS storage for the demo.
  """
  def start_storage do
    ETSStorage.start_link()
  end

  @doc """
  Stop the ETS storage and clean up.
  """
  def stop_storage do
    GenServer.stop(ETSStorage)
  end

  @doc """
  Get execution by ID for debugging.
  """
  def get_execution(execution_id) do
    ETSStorage.get_execution(execution_id)
  end

  @doc """
  List all executions for debugging.
  """
  def list_executions do
    ETSStorage.list_executions()
  end
end
