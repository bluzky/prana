defmodule Prana.GraphExecutor do
  @moduledoc """
  GraphExecutor orchestrates workflow execution using NodeExecutor as building block.

  Handles core execution patterns:
  1. Sequential execution 
  2. Conditional branching
  3. Fan-out/Fan-in parallel execution
  4. Error routing
  5. Wait/suspension

  Uses Task-based parallel coordination and port-based data routing.
  """

  alias Prana.{Workflow, Node, Connection, Execution, ExecutionContext, NodeExecution}
  alias Prana.{NodeExecutor, Middleware, ExpressionEngine}
  alias Prana.GraphExecutor.Helpers
  alias Prana.{RetryHandler, ExecutionPlanner, ExecutionPlan}

  require Logger

  @type execution_result ::
          {:ok, ExecutionContext.t()}
          | {:error, term()}
          | {:suspended, ExecutionContext.t()}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Execute a workflow starting from a specific trigger node.

  ## Parameters
  - `workflow` - Workflow definition to execute
  - `trigger_node_id` - ID of the trigger node to start execution from
  - `input_data` - Initial input data for workflow
  - `opts` - Execution options (timeout, mode, etc.)

  ## Returns
  - `{:ok, context}` - Successful completion
  - `{:error, reason}` - Execution failed 
  - `{:suspended, context}` - Workflow suspended (waiting)
  """
  @spec execute_workflow(Workflow.t(), String.t(), map(), keyword()) :: execution_result()
  def execute_workflow(%Workflow{} = workflow, trigger_node_id, input_data, opts \\ []) do
    # 1. Create execution instance
    execution = create_execution(workflow, input_data, opts)

    # 2. Initialize context
    context = ExecutionContext.new(workflow, execution)

    # 3. Emit workflow started event
    emit_workflow_event(:execution_started, context, %{input_data: input_data, trigger_node_id: trigger_node_id})

    # 4. Plan execution with specified trigger node
    case ExecutionPlanner.plan_execution(workflow, trigger_node_id) do
      {:ok, plan} ->
        # 5. Execute main workflow loop
        execute_workflow_loop(plan, context)

      {:error, reason} ->
        emit_workflow_event(:execution_failed, context, %{error: reason})
        {:error, reason}
    end
  end

  @doc """
  Execute workflow asynchronously starting from a specific trigger node.
  """
  @spec execute_workflow_async(Workflow.t(), String.t(), map(), keyword()) :: {:ok, Task.t()} | {:error, term()}
  def execute_workflow_async(workflow, trigger_node_id, input_data, opts \\ []) do
    task =
      Task.async(fn ->
        execute_workflow(workflow, trigger_node_id, input_data, opts)
      end)

    {:ok, task}
  end

  @doc """
  Resume a suspended workflow execution.
  """
  @spec resume_workflow(Execution.t(), String.t()) :: execution_result()
  def resume_workflow(%Execution{} = execution, resume_token) do
    if execution.resume_token == resume_token do
      # Reconstruct context and continue
      context = Helpers.rebuild_execution_context(execution)
      workflow = Helpers.get_workflow_definition(execution.workflow_id, execution.workflow_version)

      case ExecutionPlanner.plan_execution(workflow, nil) do
        {:ok, plan} -> continue_workflow_execution(plan, context)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_resume_token}
    end
  end

  # ============================================================================
  # Main Execution Loop
  # ============================================================================

  @spec execute_workflow_loop(ExecutionPlan.t(), ExecutionContext.t()) :: execution_result()
  defp execute_workflow_loop(%ExecutionPlan{} = plan, %ExecutionContext{} = context) do
    case find_ready_nodes(plan, context) do
      [] ->
        # No more nodes ready to execute
        check_workflow_completion(plan, context)

      ready_nodes ->
        # Execute batch of ready nodes
        case execute_nodes_batch(ready_nodes, context) do
          {:ok, node_executions, updated_context} ->
            # Route outputs and continue
            routed_context = route_batch_outputs(node_executions, plan, updated_context)
            execute_workflow_loop(plan, routed_context)

          {:partial_success, successes, failures, updated_context} ->
            # Handle partial success
            case Helpers.handle_batch_failures(failures, plan, updated_context) do
              {:continue, recovery_context} ->
                routed_context = route_batch_outputs(successes, plan, recovery_context)
                execute_workflow_loop(plan, routed_context)

              {:retry, retry_context, retry_nodes} ->
                # Handle retries for failed nodes
                case execute_retry_batch(retry_nodes, plan, retry_context) do
                  {:ok, retry_successes, final_context} ->
                    # Combine original successes with retry successes
                    all_successes = successes ++ retry_successes
                    routed_context = route_batch_outputs(all_successes, plan, final_context)
                    execute_workflow_loop(plan, routed_context)

                  {:partial_success, retry_successes, final_failures, final_context} ->
                    # Some retries succeeded, others failed permanently
                    all_successes = successes ++ retry_successes
                    routed_context = route_batch_outputs(all_successes, plan, final_context)
                    execute_workflow_loop(plan, routed_context)

                  {:error, reason} ->
                    emit_workflow_event(:execution_failed, retry_context, %{error: reason})
                    {:error, reason}
                end

              {:stop, reason} ->
                emit_workflow_event(:execution_failed, updated_context, %{error: reason})
                {:error, reason}

              {:suspend, suspend_context, resume_token} ->
                emit_workflow_event(:execution_suspended, suspend_context, %{resume_token: resume_token})
                {:suspended, suspend_context}
            end

          {:error, reason} ->
            emit_workflow_event(:execution_failed, context, %{error: reason})
            {:error, reason}
        end
    end
  end

  # ============================================================================
  # Ready Node Detection
  # ============================================================================

  @spec find_ready_nodes(ExecutionPlan.t(), ExecutionContext.t()) :: [Node.t()]
  defp find_ready_nodes(%ExecutionPlan{} = plan, %ExecutionContext{} = context) do
    ExecutionPlanner.find_ready_nodes(
      plan, 
      context.completed_nodes, 
      context.failed_nodes, 
      context.pending_nodes
    )
  end



  # ============================================================================
  # Helper Functions for Connection Validation
  # ============================================================================

  @spec get_node_output_port(ExecutionContext.t(), String.t()) :: String.t() | nil
  defp get_node_output_port(%ExecutionContext{} = context, node_id) do
    # Look up the output port from node execution results
    get_in(context.metadata, [:node_outputs, node_id, :output_port])
  end

  # ============================================================================
  # Batch Node Execution
  # ============================================================================

  @spec execute_nodes_batch([Node.t()], ExecutionContext.t()) ::
          {:ok, [NodeExecution.t()], ExecutionContext.t()}
          | {:partial_success, [NodeExecution.t()], [NodeExecution.t()], ExecutionContext.t()}
          | {:error, term()}
  defp execute_nodes_batch([node], %ExecutionContext{} = context) do
    # Single node - execute directly without Task overhead
    case execute_single_node_with_events(node, context) do
      {:ok, node_execution, updated_context} ->
        {:ok, [node_execution], updated_context}

      {:error, {reason, failed_execution}} ->
        {:partial_success, [], [failed_execution], context}
    end
  end

  defp execute_nodes_batch(nodes, %ExecutionContext{} = context) when length(nodes) > 1 do
    # Multiple nodes - execute in parallel using Tasks
    coordinate_parallel_execution(nodes, context)
  end

  @spec coordinate_parallel_execution([Node.t()], ExecutionContext.t()) ::
          {:ok, [NodeExecution.t()], ExecutionContext.t()}
          | {:partial_success, [NodeExecution.t()], [NodeExecution.t()], ExecutionContext.t()}
          | {:error, term()}
  defp coordinate_parallel_execution(nodes, %ExecutionContext{} = context) do
    # Emit batch started event
    emit_batch_event(:batch_execution_started, context, %{
      node_count: length(nodes),
      node_ids: Enum.map(nodes, & &1.id)
    })

    # Mark all nodes as pending
    pending_context =
      Enum.reduce(nodes, context, fn node, acc ->
        ExecutionContext.mark_node_pending(acc, node.id)
      end)

    # Start all node executions as supervised tasks
    tasks =
      Enum.map(nodes, fn node ->
        Task.async(fn ->
          execute_single_node_with_events(node, pending_context)
        end)
      end)

    # Wait for all tasks with timeout
    timeout = get_batch_timeout(nodes, context)

    case Task.yield_many(tasks, timeout) do
      results when is_list(results) ->
        Helpers.process_batch_results(results, nodes, pending_context)

      :timeout ->
        # Kill all tasks and return timeout error
        Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
        {:error, :batch_execution_timeout}
    end
  end

  @spec execute_single_node_with_events(Node.t(), ExecutionContext.t()) ::
          {:ok, NodeExecution.t(), ExecutionContext.t()} | {:error, {term(), NodeExecution.t()}}
  defp execute_single_node_with_events(%Node{} = node, %ExecutionContext{} = context) do
    # Emit node started event
    emit_node_event(:node_started, context, node, %{})

    # Execute using NodeExecutor
    case NodeExecutor.execute_node(node, context, []) do
      {:ok, node_execution, updated_context} ->
        # Store node output info for dependency checking
        output_context = store_node_output_info(updated_context, node.id, node_execution)

        # Emit node completed event
        emit_node_event(:node_completed, output_context, node, %{
          output_data: node_execution.output_data,
          output_port: node_execution.output_port,
          duration_ms: node_execution.duration_ms
        })

        {:ok, node_execution, output_context}

      {:error, {reason, failed_execution}} ->
        # Emit node failed event
        emit_node_event(:node_failed, context, node, %{
          error_data: reason,
          duration_ms: failed_execution.duration_ms
        })

        {:error, {reason, failed_execution}}
    end
  end

  # ============================================================================
  # Retry Execution
  # ============================================================================

  @spec execute_retry_batch([{Node.t(), NodeExecution.t()}], ExecutionPlan.t(), ExecutionContext.t()) ::
          {:ok, [NodeExecution.t()], ExecutionContext.t()}
          | {:partial_success, [NodeExecution.t()], [NodeExecution.t()], ExecutionContext.t()}
          | {:error, term()}
  defp execute_retry_batch(retry_nodes, %ExecutionPlan{} = plan, %ExecutionContext{} = context) do
    # Emit retry batch started event
    emit_batch_event(:retry_batch_started, context, %{
      retry_count: length(retry_nodes),
      retry_nodes: Enum.map(retry_nodes, fn {node, _} -> node.id end)
    })

    # Process each retry with proper delay
    retry_results =
      Enum.map(retry_nodes, fn {node, failed_execution} ->
        execute_single_retry_with_delay(node, failed_execution, context)
      end)

    # Separate successes and failures
    {successes, failures} =
      Enum.split_with(retry_results, fn
        {:ok, _node_execution, _context} -> true
        {:error, _} -> false
      end)

    successful_executions = Enum.map(successes, fn {:ok, node_execution, _} -> node_execution end)
    failed_executions = Enum.map(failures, fn {:error, {_, failed_execution}} -> failed_execution end)

    # Update context with retry results
    updated_context =
      context
      |> Helpers.update_context_with_successes(successful_executions)
      |> Helpers.update_context_with_failures(failed_executions)

    case {length(successful_executions), length(failed_executions)} do
      {success_count, 0} when success_count > 0 ->
        {:ok, successful_executions, updated_context}

      {success_count, failure_count} when success_count > 0 and failure_count > 0 ->
        {:partial_success, successful_executions, failed_executions, updated_context}

      {0, failure_count} when failure_count > 0 ->
        {:error, {:all_retries_failed, failed_executions}}

      {0, 0} ->
        {:error, :no_retry_results}
    end
  end

  @spec execute_single_retry_with_delay(Node.t(), NodeExecution.t(), ExecutionContext.t()) ::
          {:ok, NodeExecution.t(), ExecutionContext.t()} | {:error, {term(), NodeExecution.t()}}
  defp execute_single_retry_with_delay(%Node{} = node, %NodeExecution{} = failed_execution, %ExecutionContext{} = context) do
    # Calculate and apply retry delay
    if node.retry_policy do
      retry_delay = RetryHandler.calculate_retry_delay(node.retry_policy, failed_execution.retry_count)

      # Emit retry delay event
      emit_node_event(:node_retry_delay, context, node, %{
        retry_count: failed_execution.retry_count + 1,
        delay_ms: retry_delay
      })

      # Apply delay
      :timer.sleep(retry_delay)
    end

    # Create new execution for retry
    retry_execution = RetryHandler.prepare_retry_execution(failed_execution)

    # Emit retry started event
    emit_node_event(:node_retry_started, context, node, %{
      retry_count: retry_execution.retry_count,
      original_error: failed_execution.error_data
    })

    # Execute retry using NodeExecutor
    case NodeExecutor.execute_node(node, context, []) do
      {:ok, completed_execution, updated_context} ->
        # Update retry count in successful execution
        final_execution = %{completed_execution | retry_count: retry_execution.retry_count}

        # Store retry success info
        retry_context = store_retry_success_info(updated_context, node.id, final_execution)

        # Emit retry success event
        emit_node_event(:node_retry_succeeded, retry_context, node, %{
          retry_count: retry_execution.retry_count,
          final_attempt: true
        })

        {:ok, final_execution, retry_context}

      {:error, {reason, new_failed_execution}} ->
        # Update retry count in failed execution
        final_failed_execution = %{new_failed_execution | retry_count: retry_execution.retry_count}

        # Emit retry failed event
        emit_node_event(:node_retry_failed, context, node, %{
          retry_count: retry_execution.retry_count,
          error_data: reason,
          will_retry_again: RetryHandler.should_retry?(node, final_failed_execution)
        })

        {:error, {reason, final_failed_execution}}
    end
  end

  # ============================================================================
  # Output Routing & Data Flow
  # ============================================================================

  @spec route_batch_outputs([NodeExecution.t()], ExecutionPlan.t(), ExecutionContext.t()) :: ExecutionContext.t()
  defp route_batch_outputs(node_executions, %ExecutionPlan{} = plan, %ExecutionContext{} = context) do
    Enum.reduce(node_executions, context, fn node_execution, acc_context ->
      route_node_output(node_execution, plan, acc_context)
    end)
  end

  @spec route_node_output(NodeExecution.t(), ExecutionPlan.t(), ExecutionContext.t()) :: ExecutionContext.t()
  defp route_node_output(%NodeExecution{status: :completed} = node_execution, %ExecutionPlan{} = plan, context) do
    # Find outgoing connections from this node's output port
    connections = Map.get(plan.connection_map, {node_execution.node_id, node_execution.output_port}, [])

    # Route data through each valid connection
    Enum.reduce(connections, context, fn connection, acc_context ->
      route_connection_data(connection, node_execution, acc_context)
    end)
  end

  defp route_node_output(%NodeExecution{status: :failed}, _plan, context) do
    # Failed nodes don't route data
    context
  end

  @spec route_connection_data(Connection.t(), NodeExecution.t(), ExecutionContext.t()) :: ExecutionContext.t()
  defp route_connection_data(%Connection{} = connection, %NodeExecution{} = node_execution, %ExecutionContext{} = context) do
    # 1. Check connection conditions
    if evaluate_connection_conditions(connection.conditions, context) do
      # 2. Apply data mapping
      mapped_data =
        apply_data_mapping(
          node_execution.output_data,
          connection.data_mapping,
          context
        )

      # 3. Store routed data for target node
      store_routed_data(context, connection.to_node_id, connection.to_port, mapped_data)
    else
      # Conditions not met, skip routing
      context
    end
  end

  @spec apply_data_mapping(term(), map(), ExecutionContext.t()) :: term()
  defp apply_data_mapping(output_data, data_mapping, %ExecutionContext{} = context) when map_size(data_mapping) == 0 do
    # No mapping, pass through original data
    output_data
  end

  defp apply_data_mapping(output_data, data_mapping, %ExecutionContext{} = context) do
    # Build expression context
    expression_context = %{
      "output" => output_data,
      "input" => context.input,
      "nodes" => context.nodes,
      "variables" => context.variables
    }

    # Process mapping expressions
    case ExpressionEngine.process_map(data_mapping, expression_context) do
      {:ok, mapped_data} -> mapped_data
      # Fallback to original data
      {:error, _reason} -> output_data
    end
  end

  @spec evaluate_connection_conditions([Prana.Condition.t()], ExecutionContext.t()) :: boolean()
  defp evaluate_connection_conditions([], _context), do: true

  defp evaluate_connection_conditions(conditions, %ExecutionContext{} = context) do
    # For now, assume all conditions must pass (AND logic)
    expression_context = %{
      "input" => context.input,
      "nodes" => context.nodes,
      "variables" => context.variables
    }

    Enum.all?(conditions, fn condition ->
      evaluate_single_condition(condition, expression_context)
    end)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @spec create_execution(Workflow.t(), map(), keyword()) :: Execution.t()
  defp create_execution(%Workflow{} = workflow, input_data, opts) do
    trigger_type = Keyword.get(opts, :trigger_type, "api")
    trigger_node_id = Keyword.get(opts, :trigger_node_id)

    workflow.id
    |> Execution.new(workflow.version, trigger_type, input_data, trigger_node_id)
    |> Execution.start()
  end

  @spec store_node_output_info(ExecutionContext.t(), String.t(), NodeExecution.t()) :: ExecutionContext.t()
  defp store_node_output_info(%ExecutionContext{} = context, node_id, %NodeExecution{} = node_execution) do
    output_info = %{
      output_port: node_execution.output_port,
      status: node_execution.status,
      completed_at: node_execution.completed_at
    }

    metadata = Map.put(context.metadata, :node_outputs, %{})
    updated_metadata = put_in(metadata, [:node_outputs, node_id], output_info)
    %{context | metadata: updated_metadata}
  end

  @spec store_routed_data(ExecutionContext.t(), String.t(), String.t(), term()) :: ExecutionContext.t()
  defp store_routed_data(%ExecutionContext{} = context, target_node_id, target_port, data) do
    routed_key = "#{target_node_id}:#{target_port}"

    routed_data =
      context.metadata
      |> Map.get(:routed_data, %{})
      |> Map.put(routed_key, data)

    updated_metadata = Map.put(context.metadata, :routed_data, routed_data)
    %{context | metadata: updated_metadata}
  end

  @spec get_batch_timeout([Node.t()], ExecutionContext.t()) :: integer()
  defp get_batch_timeout(nodes, _context) do
    # Calculate timeout based on node timeout settings
    max_node_timeout =
      nodes
      |> Enum.map(fn node -> node.timeout_seconds || 30 end)
      |> Enum.max()

    # Convert to milliseconds
    max_node_timeout * 1000
  end

  @spec check_workflow_completion(ExecutionPlan.t(), ExecutionContext.t()) :: execution_result()
  defp check_workflow_completion(%ExecutionPlan{} = plan, %ExecutionContext{} = context) do
    total_nodes = plan.total_nodes
    completed_count = MapSet.size(context.completed_nodes)
    failed_count = MapSet.size(context.failed_nodes)

    cond do
      completed_count == total_nodes ->
        # All nodes completed successfully
        output_data = Helpers.extract_workflow_output(context)
        final_execution = Execution.complete(context.execution, output_data)
        final_context = %{context | execution: final_execution}

        emit_workflow_event(:execution_completed, final_context, %{
          output_data: output_data,
          duration_ms: Execution.duration(final_execution)
        })

        {:ok, final_context}

      completed_count + failed_count == total_nodes ->
        # All nodes processed, but some failed
        error_data = %{
          completed_nodes: completed_count,
          failed_nodes: failed_count,
          failed_node_ids: MapSet.to_list(context.failed_nodes)
        }

        final_execution = Execution.fail(context.execution, error_data)
        final_context = %{context | execution: final_execution}

        emit_workflow_event(:execution_failed, final_context, %{error_data: error_data})
        {:error, :workflow_completed_with_failures}

      true ->
        # Workflow is stuck/deadlocked
        error_data = %{
          completed_nodes: completed_count,
          failed_nodes: failed_count,
          pending_nodes: MapSet.size(context.pending_nodes),
          total_nodes: total_nodes
        }

        emit_workflow_event(:execution_failed, context, %{error_data: error_data})
        {:error, :workflow_deadlock}
    end
  end

  # ============================================================================
  # Event Emission
  # ============================================================================

  @spec emit_workflow_event(atom(), ExecutionContext.t(), map()) :: term()
  defp emit_workflow_event(event, %ExecutionContext{} = context, additional_data) do
    event_data =
      Map.merge(
        %{execution_id: context.execution_id, workflow_id: context.workflow.id, workflow_name: context.workflow.name},
        additional_data
      )

    Middleware.call(event, event_data)
  end

  @spec emit_node_event(atom(), ExecutionContext.t(), Node.t(), map()) :: term()
  defp emit_node_event(event, %ExecutionContext{} = context, %Node{} = node, additional_data) do
    event_data =
      Map.merge(
        %{execution_id: context.execution_id, node_id: node.id, node_name: node.name, node_type: node.type},
        additional_data
      )

    Middleware.call(event, event_data)
  end

  @spec emit_batch_event(atom(), ExecutionContext.t(), map()) :: term()
  defp emit_batch_event(event, %ExecutionContext{} = context, additional_data) do
    event_data = Map.merge(%{execution_id: context.execution_id}, additional_data)

    Middleware.call(event, event_data)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @spec store_retry_success_info(ExecutionContext.t(), String.t(), NodeExecution.t()) :: ExecutionContext.t()
  defp store_retry_success_info(%ExecutionContext{} = context, node_id, %NodeExecution{} = execution) do
    retry_info = %{
      retry_count: execution.retry_count,
      final_attempt: true,
      success_on_retry: execution.retry_count > 0
    }

    updated_metadata = put_in(context.metadata, [:retry_info, node_id], retry_info)
    %{context | metadata: updated_metadata}
  end

  # ============================================================================
  # Placeholder Functions (To Be Implemented)
  # ============================================================================

  defp continue_workflow_execution(_plan, _context), do: {:ok, %ExecutionContext{}}
  defp evaluate_single_condition(_condition, _context), do: true
end
