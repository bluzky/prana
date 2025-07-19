defmodule Examples.WorkflowRunner do
  @moduledoc """
  Example WorkflowRunner implementation following the integration flow diagram.

  This module demonstrates how applications can integrate with Prana to handle
  workflow execution, suspension/resume patterns, and database persistence.

  ## Integration Flow

  1. execute_workflow/3 - Main entry point for workflow execution
  2. resume_workflow/2 - Resume suspended workflows
  3. handle_result/1 - Process execution results and handle suspensions
  4. handle_suspend/1 - Handle different suspension types

  ## Usage

      # Execute a workflow
      {:ok, result} = Examples.WorkflowRunner.execute_workflow(workflow, input, opts)

      # Resume a suspended workflow
      {:ok, result} = Examples.WorkflowRunner.resume_workflow(execution, resume_input)
  """

  alias Prana.Core.Execution
  alias Prana.Core.ExecutionGraph
  alias Prana.GraphExecutor
  alias Prana.Workflow
  alias Prana.WorkflowCompiler

  require Logger

  @doc """
  Execute a workflow with input data and options.

  Follows the integration flow:
  1. Build execution graph
  2. Initialize execution context
  3. Insert execution into database
  4. Execute graph via GraphExecutor
  5. Handle results (completion or suspension)
  """
  def execute_workflow(workflow, input, opts \\ []) do
    Logger.info("Starting workflow execution")

    with {:ok, execution_graph} <- build_graph(workflow),
         {:ok, execution} <- init_execution(execution_graph, input, opts),
         {:ok, persisted_execution} <- insert_db(execution),
         {:ok, result} <- GraphExecutor.execute_workflow(persisted_execution) do
      handle_result(result)
    else
      error ->
        Logger.error("Workflow execution failed: #{inspect(error)}")
        error
    end
  end

  @doc """
  Resume a suspended workflow with new input data.

  Follows the resume flow:
  1. Rebuild execution graph from persisted state
  2. Call GraphExecutor.resume_workflow
  3. Handle results (completion or further suspension)
  """
  def resume_workflow(execution, resume_input) do
    Logger.info("Resuming workflow execution: #{execution.id}")

    with {:ok, result} <- GraphExecutor.resume_workflow(execution, resume_input) do
      handle_result(result)
    else
      error ->
        Logger.error("Workflow resume failed: #{inspect(error)}")
        error
    end
  end

  # Private implementation functions

  defp build_graph(workflow) do
    Logger.debug("Building execution graph")
    WorkflowCompiler.compile(workflow)
  end

  defp init_execution(execution_graph, input, opts) do
    Logger.debug("Initializing execution context")
    
    # Build context for GraphExecutor.initialize_execution
    context = %{
      variables: Map.get(opts, :variables, %{}),
      metadata: Map.get(opts, :metadata, %{}),
      env: Map.get(opts, :env, %{})
    }
    
    # Use GraphExecutor.initialize_execution for consistent initialization
    case GraphExecutor.initialize_execution(execution_graph, context) do
      {:ok, execution} ->
        # Enhance execution with application-specific fields
        enhanced_execution = %{execution | 
          input: input,
          options: opts,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
        {:ok, enhanced_execution}
        
      error -> error
    end
  end

  defp insert_db(execution) do
    Logger.debug("Persisting execution to database")
    # In a real application, this would save to your database
    # For this example, we'll simulate database persistence
    persist_execution(execution)
  end

  defp rebuild_graph(execution) do
    Logger.debug("Rebuilding execution graph from persisted state")
    # In a real application, this would load the workflow from database
    # and rebuild the execution graph
    case load_workflow_by_id(execution.workflow_id) do
      {:ok, workflow} -> WorkflowCompiler.compile(workflow)
      error -> error
    end
  end

  defp handle_result(result_tuple) do
    case result_tuple do
      {:ok, execution} ->
        Logger.info("Workflow completed successfully")
        update_execution_db(execution, "completed")
        {:ok, execution}

      {:suspend, execution} ->
        Logger.info("Workflow suspended")
        handle_suspend(execution)

      {:error, execution} ->
        Logger.error("Workflow execution failed")
        update_execution_db(execution, "failed")
        {:error, execution}
    end
  end

  defp handle_suspend(suspension_data) do
    case suspension_data.suspend_type do
      # Handle wait operations (timer, scheduler, webhook)
      suspend_type when suspend_type in [:timer, :scheduler, :webhook] ->
        Logger.info("Handling wait suspension: #{suspend_type}")
        handle_wait_suspension(suspension_data)

      # Handle sub-workflow operations
      :sub_workflow ->
        Logger.info("Handling sub-workflow suspension")
        handle_sub_workflow_suspension(suspension_data)
    end
  end

  defp handle_wait_suspension(suspension_data) do
    Logger.info("Setting up wait operation: #{suspension_data.suspend_type}")

    # Update execution status to suspended
    update_execution_db(suspension_data, "suspended")

    # Set up external trigger based on suspension type
    case suspension_data.suspend_type do
      :timer ->
        schedule_timer_resume(suspension_data)

      :scheduler ->
        schedule_cron_resume(suspension_data)

      :webhook ->
        setup_webhook_listener(suspension_data)
    end

    {:ok, "suspended"}
  end

  defp handle_sub_workflow_suspension(suspension_data) do
    execution_mode = suspension_data.suspend_data.execution_mode
    sub_workflow = suspension_data.suspend_data.workflow
    sub_input = suspension_data.suspend_data.input

    Logger.info("Handling sub-workflow with mode: #{execution_mode}")

    case execution_mode do
      :synchronous ->
        # Execute immediately and continue
        Logger.info("Executing sub-workflow synchronously")

        case execute_workflow(sub_workflow, sub_input) do
          {:ok, sub_result} ->
            # Resume parent workflow with sub-workflow result
            resume_workflow(suspension_data.execution, sub_result)

          error ->
            Logger.error("Sub-workflow execution failed: #{inspect(error)}")
            error
        end

      :asynchronous ->
        # Enqueue for execution and suspend parent
        Logger.info("Enqueueing sub-workflow for asynchronous execution")
        enqueue_for_execution(sub_workflow, sub_input, suspension_data.execution)
        update_execution_db(suspension_data, "suspended")
        {:ok, "suspended"}

      :fire_and_forget ->
        # Enqueue for execution and continue parent
        Logger.info("Enqueueing sub-workflow for fire-and-forget execution")
        enqueue_for_execution(sub_workflow, sub_input, nil)
        # Continue parent workflow immediately
        resume_workflow(suspension_data.execution, %{sub_workflow: :fire_and_forget})
    end
  end

  # Database and external system integration helpers

  defp persist_execution(execution) do
    # Simulate database persistence
    Logger.debug("Persisting execution: #{execution.id}")
    {:ok, execution}
  end

  defp update_execution_db(result_data, status) do
    Logger.debug("Updating execution status to: #{status}")
    # In a real application, update your database here
    :ok
  end

  defp load_workflow_by_id(workflow_id) do
    # Simulate loading workflow from database
    Logger.debug("Loading workflow: #{workflow_id}")
    # Return a mock workflow for this example
    {:ok, %Workflow{id: workflow_id, name: "Example Workflow", nodes: %{}, connections: %{}}}
  end

  defp schedule_timer_resume(suspension_data) do
    delay_ms = suspension_data.suspend_data.delay_ms
    Logger.info("Scheduling timer resume in #{delay_ms}ms")

    # In a real application, use your preferred scheduling mechanism
    Process.send_after(self(), {:resume_workflow, suspension_data.execution, %{}}, delay_ms)
  end

  defp schedule_cron_resume(suspension_data) do
    cron_expression = suspension_data.suspend_data.cron_expression
    Logger.info("Scheduling cron resume: #{cron_expression}")

    # In a real application, integrate with a cron scheduler
    # This is just a placeholder
    :ok
  end

  defp setup_webhook_listener(suspension_data) do
    webhook_url = suspension_data.suspend_data.webhook_url
    Logger.info("Setting up webhook listener: #{webhook_url}")

    # In a real application, register webhook endpoint
    # This is just a placeholder
    :ok
  end

  defp enqueue_for_execution(workflow, input, parent_execution) do
    Logger.info("Enqueueing workflow for background execution")

    # In a real application, enqueue to your job processing system
    # For example, with Oban:
    # %{workflow: workflow, input: input, parent_execution_id: parent_execution&.id}
    # |> MyApp.Workers.WorkflowExecutor.new()
    # |> Oban.insert()

    :ok
  end

  defp generate_execution_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
  end
end
