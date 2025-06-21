defmodule Prana.GraphExecutor.Helpers do
  @moduledoc """
  Helper functions for GraphExecutor batch processing, error handling, and utilities.
  """

  alias Prana.Execution
  alias Prana.ExecutionContext
  alias Prana.ExecutionPlan
  alias Prana.RetryHandler
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.Workflow

  require Logger

  # ============================================================================
  # Batch Result Processing
  # ============================================================================

  @doc """
  Process Task.yield_many results into success/failure groups.
  """

  @spec process_batch_results(list(), [Node.t()], ExecutionContext.t()) ::
          {:ok, [NodeExecution.t()], ExecutionContext.t()}
          | {:partial_success, [NodeExecution.t()], [NodeExecution.t()], ExecutionContext.t()}
          | {:error, term()}
  def process_batch_results(task_results, nodes, %ExecutionContext{} = context) do
    {successes, failures} =
      task_results
      |> Enum.zip(nodes)
      |> Enum.split_with(fn {{_task, result}, _node} ->
        match?({:ok, {:ok, _node_execution, _context}}, {_task, result})
      end)

    # Process successful executions
    successful_executions = extract_successful_executions(successes)

    # Process failed executions
    failed_executions = extract_failed_executions(failures)

    # Update context with all results
    updated_context =
      context
      |> update_context_with_successes(successful_executions)
      |> update_context_with_failures(failed_executions)

    # Determine overall result
    case {length(successful_executions), length(failed_executions)} do
      {success_count, 0} when success_count > 0 ->
        {:ok, successful_executions, updated_context}

      {success_count, failure_count} when success_count > 0 and failure_count > 0 ->
        {:partial_success, successful_executions, failed_executions, updated_context}

      {0, failure_count} when failure_count > 0 ->
        {:error, {:all_nodes_failed, failed_executions}}

      {0, 0} ->
        {:error, :no_results}
    end
  end

  @spec extract_successful_executions(list()) :: [NodeExecution.t()]
  defp extract_successful_executions(successes) do
    Enum.map(successes, fn {{_task, {:ok, {:ok, node_execution, _context}}}, _node} ->
      node_execution
    end)
  end

  @spec extract_failed_executions(list()) :: [NodeExecution.t()]
  defp extract_failed_executions(failures) do
    Enum.map(failures, fn {{_task, result}, node} ->
      case result do
        {:ok, {:error, {_reason, failed_execution}}} ->
          failed_execution

        {:exit, reason} ->
          create_crashed_execution(node, reason)

        nil ->
          create_timeout_execution(node)

        other ->
          create_unknown_failure_execution(node, other)
      end
    end)
  end

  @spec create_crashed_execution(Node.t(), term()) :: NodeExecution.t()
  defp create_crashed_execution(%Node{} = node, reason) do
    "unknown"
    |> NodeExecution.new(node.id, %{})
    |> NodeExecution.start()
    |> NodeExecution.fail(%{
      "type" => "task_crashed",
      "reason" => inspect(reason),
      "node_id" => node.id,
      "node_name" => node.name
    })
  end

  @spec create_timeout_execution(Node.t()) :: NodeExecution.t()
  defp create_timeout_execution(%Node{} = node) do
    "unknown"
    |> NodeExecution.new(node.id, %{})
    |> NodeExecution.start()
    |> NodeExecution.fail(%{
      "type" => "task_timeout",
      "node_id" => node.id,
      "node_name" => node.name,
      "message" => "Node execution timed out"
    })
  end

  @spec create_unknown_failure_execution(Node.t(), term()) :: NodeExecution.t()
  defp create_unknown_failure_execution(%Node{} = node, result) do
    "unknown"
    |> NodeExecution.new(node.id, %{})
    |> NodeExecution.start()
    |> NodeExecution.fail(%{
      "type" => "unknown_failure",
      "result" => inspect(result),
      "node_id" => node.id,
      "node_name" => node.name
    })
  end

  # ============================================================================
  # Context Updates
  # ============================================================================

  @spec update_context_with_successes(ExecutionContext.t(), [NodeExecution.t()]) :: ExecutionContext.t()
  def update_context_with_successes(%ExecutionContext{} = context, successful_executions) do
    Enum.reduce(successful_executions, context, fn node_execution, acc_context ->
      acc_context
      |> ExecutionContext.add_node_output(node_execution.node_id, node_execution.output_data)
      |> add_execution_stats(node_execution)
      |> remove_from_pending(node_execution.node_id)
    end)
  end

  @spec update_context_with_failures(ExecutionContext.t(), [NodeExecution.t()]) :: ExecutionContext.t()
  def update_context_with_failures(%ExecutionContext{} = context, failed_executions) do
    Enum.reduce(failed_executions, context, fn node_execution, acc_context ->
      acc_context
      |> ExecutionContext.mark_node_failed(node_execution.node_id)
      |> add_execution_stats(node_execution)
      |> remove_from_pending(node_execution.node_id)
      |> store_node_error(node_execution.node_id, node_execution.error_data)
    end)
  end

  @spec add_execution_stats(ExecutionContext.t(), NodeExecution.t()) :: ExecutionContext.t()
  defp add_execution_stats(%ExecutionContext{} = context, %NodeExecution{} = node_execution) do
    stats =
      get_in(context.metadata, [:execution_stats]) ||
        %{
          total_nodes: 0,
          completed_nodes: 0,
          failed_nodes: 0,
          total_duration_ms: 0
        }

    updated_stats =
      case node_execution.status do
        :completed ->
          %{
            stats
            | completed_nodes: stats.completed_nodes + 1,
              total_duration_ms: stats.total_duration_ms + (node_execution.duration_ms || 0)
          }

        :failed ->
          %{
            stats
            | failed_nodes: stats.failed_nodes + 1,
              total_duration_ms: stats.total_duration_ms + (node_execution.duration_ms || 0)
          }

        _ ->
          stats
      end

    updated_metadata = Map.put(context.metadata, :execution_stats, updated_stats)
    %{context | metadata: updated_metadata}
  end

  @spec remove_from_pending(ExecutionContext.t(), String.t()) :: ExecutionContext.t()
  defp remove_from_pending(%ExecutionContext{} = context, node_id) do
    %{context | pending_nodes: MapSet.delete(context.pending_nodes, node_id)}
  end

  @spec store_node_error(ExecutionContext.t(), String.t(), map()) :: ExecutionContext.t()
  defp store_node_error(%ExecutionContext{} = context, node_id, error_data) do
    node_errors = get_in(context.metadata, [:node_errors]) || %{}
    updated_errors = Map.put(node_errors, node_id, error_data)

    updated_metadata = Map.put(context.metadata, :node_errors, updated_errors)
    %{context | metadata: updated_metadata}
  end

  # ============================================================================
  # Error Handling & Recovery
  # ============================================================================

  @doc """
  Handle batch failures according to error handling strategy.
  """
  @spec handle_batch_failures([NodeExecution.t()], ExecutionPlan.t(), ExecutionContext.t()) ::
          {:continue, ExecutionContext.t()}
          | {:retry, ExecutionContext.t(), [{Node.t(), NodeExecution.t()}]}
          | {:stop, term()}
          | {:suspend, ExecutionContext.t(), String.t()}
  def handle_batch_failures(failed_executions, %ExecutionPlan{} = plan, %ExecutionContext{} = context) do
    # Separate retryable and non-retryable failures
    {retryable_failures, permanent_failures} = separate_retryable_failures(failed_executions, plan)

    # Analyze failure types and determine strategy
    failure_analysis = analyze_failures(failed_executions, plan)

    case determine_recovery_strategy(failure_analysis, plan, context) do
      {:retry, retry_nodes} when length(retry_nodes) > 0 ->
        # Some nodes can be retried
        recovery_context = apply_failure_recovery(permanent_failures, context)
        {:retry, recovery_context, retry_nodes}

      :continue ->
        # Mark failed nodes and continue with rest of workflow
        recovery_context = apply_failure_recovery(failed_executions, context)
        {:continue, recovery_context}

      {:stop, reason} ->
        # Critical failure - stop entire workflow
        {:stop, reason}

      {:suspend, resume_token} ->
        # Suspend workflow for external intervention
        suspended_context = mark_workflow_suspended(context, resume_token)
        {:suspend, suspended_context, resume_token}
    end
  end

  @spec analyze_failures([NodeExecution.t()], ExecutionPlan.t()) :: map()
  defp analyze_failures(failed_executions, %ExecutionPlan{} = plan) do
    failure_types =
      Enum.group_by(failed_executions, fn execution ->
        get_in(execution.error_data, ["type"]) || "unknown"
      end)

    critical_nodes =
      Enum.filter(failed_executions, fn execution ->
        node = Map.get(plan.node_map, execution.node_id)
        node && is_critical_node?(node)
      end)

    retryable_nodes =
      Enum.filter(failed_executions, fn execution ->
        node = Map.get(plan.node_map, execution.node_id)
        node && can_retry_node?(node, execution)
      end)

    %{
      total_failures: length(failed_executions),
      failure_types: failure_types,
      critical_failures: critical_nodes,
      retryable_failures: retryable_nodes,
      failure_rate: length(failed_executions) / plan.total_nodes
    }
  end

  @spec separate_retryable_failures([NodeExecution.t()], ExecutionPlan.t()) ::
          {[{Node.t(), NodeExecution.t()}], [NodeExecution.t()]}
  defp separate_retryable_failures(failed_executions, %ExecutionPlan{} = plan) do
    failed_executions
    |> Enum.split_with(fn execution ->
      node = Map.get(plan.node_map, execution.node_id)
      node && RetryHandler.should_retry?(node, execution)
    end)
    |> then(fn {retryable_executions, permanent_executions} ->
      # Convert retryable executions to {node, execution} tuples
      retryable_with_nodes =
        Enum.map(retryable_executions, fn execution ->
          node = Map.get(plan.node_map, execution.node_id)
          {node, execution}
        end)

      {retryable_with_nodes, permanent_executions}
    end)
  end

  @spec determine_recovery_strategy(map(), ExecutionPlan.t(), ExecutionContext.t()) ::
          :continue | {:stop, term()} | {:suspend, String.t()} | {:retry, [{Node.t(), NodeExecution.t()}]}
  defp determine_recovery_strategy(%{failure_rate: rate} = analysis, _plan, _context) when rate >= 0.5 do
    # High failure rate - stop workflow
    {:stop, {:high_failure_rate, analysis}}
  end

  defp determine_recovery_strategy(%{critical_failures: critical} = analysis, _plan, _context)
       when length(critical) > 0 do
    # Critical node failures - stop workflow
    {:stop, {:critical_node_failure, analysis}}
  end

  defp determine_recovery_strategy(%{retryable_failures: retryable} = _analysis, plan, _context)
       when length(retryable) > 0 do
    # Has retryable failures - prepare retry list
    {retry_nodes, _permanent} = separate_retryable_failures(retryable, plan)
    {:retry, retry_nodes}
  end

  defp determine_recovery_strategy(_analysis, _plan, _context) do
    # Non-critical failures - continue
    :continue
  end

  @spec is_critical_node?(Node.t()) :: boolean()
  defp is_critical_node?(%Node{} = node) do
    # Check if node is marked as critical in error handling
    # Output nodes are typically critical
    get_in(node.error_handling, [:strategy]) == :stop_workflow or
      node.type == :output
  end

  @spec can_retry_node?(Node.t(), NodeExecution.t()) :: boolean()
  defp can_retry_node?(%Node{} = node, %NodeExecution{} = execution) do
    RetryHandler.should_retry?(node, execution)
  end

  @spec apply_failure_recovery([NodeExecution.t()], ExecutionContext.t()) :: ExecutionContext.t()
  defp apply_failure_recovery(failed_executions, %ExecutionContext{} = context) do
    # For now, just mark nodes as failed and continue
    # In real implementation, might apply specific recovery strategies
    Enum.reduce(failed_executions, context, fn execution, acc_context ->
      ExecutionContext.mark_node_failed(acc_context, execution.node_id)
    end)
  end

  @spec mark_workflow_suspended(ExecutionContext.t(), String.t()) :: ExecutionContext.t()
  defp mark_workflow_suspended(%ExecutionContext{} = context, resume_token) do
    suspended_execution = Execution.suspend(context.execution, resume_token)
    %{context | execution: suspended_execution}
  end

  # ============================================================================
  # Workflow State Validation
  # ============================================================================

  @doc """
  Validate workflow structure before execution.
  """
  @spec validate_workflow_structure(Workflow.t()) :: :ok | {:error, term()}
  def validate_workflow_structure(%Workflow{} = workflow) do
    with :ok <- validate_has_nodes(workflow),
         :ok <- validate_has_entry_nodes(workflow),
         :ok <- validate_connections(workflow) do
      validate_no_cycles(workflow)
    end
  end

  @spec validate_has_nodes(Workflow.t()) :: :ok | {:error, term()}
  defp validate_has_nodes(%Workflow{nodes: []}) do
    {:error, :no_nodes}
  end

  defp validate_has_nodes(%Workflow{nodes: nodes}) when length(nodes) > 0 do
    :ok
  end

  @spec validate_has_entry_nodes(Workflow.t()) :: :ok | {:error, term()}
  defp validate_has_entry_nodes(%Workflow{} = workflow) do
    entry_nodes = Workflow.get_entry_nodes(workflow)

    case length(entry_nodes) do
      0 -> {:error, :no_entry_nodes}
      _ -> :ok
    end
  end

  @spec validate_connections(Workflow.t()) :: :ok | {:error, term()}
  defp validate_connections(%Workflow{nodes: nodes, connections: connections}) do
    node_ids = MapSet.new(nodes, & &1.id)

    invalid_connections =
      Enum.reject(connections, fn conn ->
        MapSet.member?(node_ids, conn.from_node_id) and
          MapSet.member?(node_ids, conn.to_node_id)
      end)

    case invalid_connections do
      [] -> :ok
      invalid -> {:error, {:invalid_connections, invalid}}
    end
  end

  @spec validate_no_cycles(Workflow.t()) :: :ok | {:error, term()}
  defp validate_no_cycles(%Workflow{} = workflow) do
    # Simple cycle detection using DFS
    case detect_cycles(workflow) do
      [] -> :ok
      cycles -> {:error, {:cycles_detected, cycles}}
    end
  end

  @spec detect_cycles(Workflow.t()) :: [list()]
  defp detect_cycles(%Workflow{} = _workflow) do
    # Simplified implementation - real version would use proper graph algorithms
    # like DFS with color coding to detect back edges
    []
  end

  # ============================================================================
  # Context Reconstruction
  # ============================================================================

  @doc """
  Rebuild execution context from persisted execution state.
  """
  @spec rebuild_execution_context(Execution.t()) :: ExecutionContext.t()
  def rebuild_execution_context(%Execution{} = execution) do
    # This would reconstruct the context from persisted state
    # For now, return a basic context structure
    workflow = get_workflow_definition(execution.workflow_id, execution.workflow_version)

    %ExecutionContext{
      execution_id: execution.id,
      workflow: workflow,
      execution: execution,
      nodes: execution.context_data["nodes"] || %{},
      variables: workflow.variables,
      input: execution.input_data,
      pending_nodes: MapSet.new(execution.context_data["pending_nodes"] || []),
      completed_nodes: MapSet.new(execution.context_data["completed_nodes"] || []),
      failed_nodes: MapSet.new(execution.context_data["failed_nodes"] || []),
      metadata: execution.context_data["metadata"] || %{}
    }
  end

  @doc """
  Extract final workflow output from execution context.
  """
  @spec extract_workflow_output(ExecutionContext.t()) :: map()
  def extract_workflow_output(%ExecutionContext{} = context) do
    # Find output nodes and collect their results
    output_nodes =
      Enum.filter(context.workflow.nodes, fn node ->
        node.type == :output
      end)

    case output_nodes do
      [] ->
        # No explicit output nodes - return all node results
        %{
          "nodes" => context.nodes,
          "execution_stats" => get_in(context.metadata, [:execution_stats])
        }

      output_nodes ->
        # Collect results from output nodes
        output_data =
          Map.new(output_nodes, fn node -> {node.custom_id, Map.get(context.nodes, node.custom_id)} end)

        %{
          "outputs" => output_data,
          "execution_stats" => get_in(context.metadata, [:execution_stats])
        }
    end
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Get workflow definition by ID and version.
  This is a placeholder - real implementation would fetch from storage.
  """
  @spec get_workflow_definition(String.t(), integer()) :: Workflow.t()
  def get_workflow_definition(_workflow_id, _version) do
    # This would fetch workflow definition from storage
    # For now, return empty workflow
    %Workflow{
      id: "placeholder",
      name: "Placeholder Workflow",
      nodes: [],
      connections: [],
      variables: %{},
      settings: %Prana.WorkflowSettings{},
      metadata: %{}
    }
  end
end
