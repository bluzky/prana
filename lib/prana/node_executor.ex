defmodule Prana.NodeExecutor do
  @moduledoc """
  Executes individual nodes within a workflow.

  Handles:
  - Expression-based input preparation using ExpressionEngine
  - Action invocation via MFA pattern
  - Output processing and port determination
  - Basic error handling
  """
  alias Prana.Core.Error
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecution

  @doc """
  Execute a single node with the given execution and routed input.

  ## Parameters
  - `node` - The node to execute
  - `execution` - Current execution state (with __runtime initialized)
  - `routed_input` - Input data routed to this node's input ports
  - `execution_index` - Global execution order index
  - `run_index` - Per-node iteration index

  ## Returns
  - `{:ok, node_execution, updated_execution}` - Successful execution with updated WorkflowExecution
  - `{:suspend, node_execution}` - Node suspended for async coordination
  - `{:error, reason}` - Execution failed
  """
  @spec execute_node(Node.t(), Prana.WorkflowExecution.t(), map(), map()) ::
          {:ok, NodeExecution.t(), Prana.WorkflowExecution.t()}
          | {:suspend, NodeExecution.t()}
          | {:error, term()}
  def execute_node(%Node{} = node, %Prana.WorkflowExecution{} = execution, routed_input, execution_context \\ %{}) do
    execution_index = Map.get(execution_context, :execution_index, 0)
    run_index = Map.get(execution_context, :run_index, 0)
    node_execution = create_node_execution(node, execution_index, run_index)
    action_context = build_expression_context(node_execution, execution, routed_input, execution_context)

    with {:ok, prepared_params} <- prepare_params(node, action_context),
         {:ok, action} <- get_action(node) do
      node_execution = %{node_execution | params: prepared_params}
      handle_action_execution(node, action, prepared_params, action_context, node_execution, execution)
    else
      {:error, reason} ->
        handle_execution_error(node, node_execution, reason)
    end
  end

  @doc """
  Retry a failed node execution by rebuilding input and re-executing the action.

  This function is called specifically for retry scenarios and rebuilds the input
  fresh from the current execution state, then calls action.execute().

  ## Parameters
  - `node` - The node to retry
  - `execution` - Current execution state  
  - `failed_node_execution` - The failed NodeExecution to retry
  - `execution_context` - Execution context (execution_index, run_index, etc.)

  ## Returns
  Same as execute_node: {:ok, node_execution, updated_execution} | {:suspend, suspended_execution} | {:error, reason}
  """
  @spec retry_node(Node.t(), Prana.WorkflowExecution.t(), NodeExecution.t(), map()) ::
          {:ok, NodeExecution.t(), Prana.WorkflowExecution.t()}
          | {:suspend, NodeExecution.t()}
          | {:error, {term(), NodeExecution.t()}}
  def retry_node(
        %Node{} = node,
        %Prana.WorkflowExecution{} = execution,
        %NodeExecution{} = failed_node_execution,
        execution_context \\ %{}
      ) do
    # Rebuild input fresh - same as execute_node
    routed_input = Prana.WorkflowExecution.extract_multi_port_input(node, execution)

    # Resume the failed execution
    resumed_node_execution = NodeExecution.resume(failed_node_execution)

    # Build context and execute action (same as normal execution)  
    action_context = build_expression_context(resumed_node_execution, execution, routed_input, execution_context)

    with {:ok, prepared_params} <- prepare_params(node, action_context),
         {:ok, action} <- get_action(node) do
      node_execution = %{resumed_node_execution | params: prepared_params}

      # Handle action execution with retry context preservation
      case invoke_action(action, prepared_params, action_context) do
        {:ok, output_data, output_port} ->
          completed_execution = NodeExecution.complete(node_execution, output_data, output_port)
          updated_execution = Prana.WorkflowExecution.complete_node(execution, completed_execution)
          {:ok, completed_execution, updated_execution}

        {:ok, output_data, output_port, state_updates} ->
          {node_context_updates, workflow_state_updates} = extract_node_context_updates(state_updates)
          completed_execution = NodeExecution.complete(node_execution, output_data, output_port)

          updated_execution =
            complete_node_with_context_update(
              execution,
              completed_execution,
              node_context_updates,
              workflow_state_updates
            )

          {:ok, completed_execution, updated_execution}

        {:suspend, suspension_type, suspension_data} ->
          suspended_execution = NodeExecution.suspend(node_execution, suspension_type, suspension_data)
          {:suspend, suspended_execution}

        {:error, reason} ->
          # For retry failures, we need to handle retry logic with proper attempt counting
          handle_retry_failure(node, failed_node_execution, resumed_node_execution, reason)
      end
    else
      {:error, reason} ->
        # For preparation failures, also handle with retry context
        handle_retry_failure(node, failed_node_execution, resumed_node_execution, reason)
    end
  end

  # Handle retry failures with proper attempt counting
  defp handle_retry_failure(node, original_failed_execution, current_node_execution, reason) do
    # Get current attempt number from original failure context
    current_attempt = get_current_attempt_number(original_failed_execution)

    # Check if the ORIGINAL error (the one that caused the first retry) was retryable
    # This prevents retrying configuration errors even if they later cause different errors
    original_error = original_failed_execution.suspension_data["original_error"]

    if original_error && not is_retryable_error?(original_error) do
      # Original error was not retryable - fail immediately
      failed_execution = NodeExecution.fail(current_node_execution, original_error)
      {:error, {original_error, failed_execution}}
    else
      if should_retry_with_attempt?(node, current_attempt, reason) do
        # Prepare retry suspension data with incremented attempt
        next_attempt = current_attempt + 1

        retry_suspension_data = %{
          "resume_at" => DateTime.add(DateTime.utc_now(), node.settings.retry_delay_ms, :millisecond),
          "attempt_number" => next_attempt,
          "max_attempts" => node.settings.max_retries,
          # Preserve original error if it exists
          "original_error" => original_error || reason
        }

        # Suspend for retry
        suspended_execution = NodeExecution.suspend(current_node_execution, :retry, retry_suspension_data)
        {:suspend, suspended_execution}
      else
        # No more retries - final failure
        failed_execution = NodeExecution.fail(current_node_execution, reason)
        {:error, {reason, failed_execution}}
      end
    end
  end

  # Check if we should retry based on current attempt number
  defp should_retry_with_attempt?(node, current_attempt, error_reason) do
    settings = node.settings

    settings.retry_on_failed and settings.max_retries > 0 and current_attempt < settings.max_retries and
      is_retryable_error?(error_reason)
  end

  @doc """
  Resume a suspended node execution with resume data.

  ## Parameters
  - `node` - The node definition
  - `execution` - Current execution state (with __runtime initialized)
  - `suspended_node_execution` - The suspended NodeExecution to resume
  - `resume_data` - Data to complete the suspended execution with

  ## Returns
  - `{:ok, node_execution, updated_execution}` - Successfully resumed with updated WorkflowExecution
  - `{:error, {reason, failed_node_execution}}` - Resume failed
  """
  @spec resume_node(Node.t(), Prana.WorkflowExecution.t(), NodeExecution.t(), map()) ::
          {:ok, NodeExecution.t(), Prana.WorkflowExecution.t()} | {:error, {term(), NodeExecution.t()}}
  def resume_node(
        %Node{} = node,
        %Prana.WorkflowExecution{} = execution,
        %NodeExecution{} = suspended_node_execution,
        resume_data,
        execution_context \\ %{}
      ) do
    context = build_expression_context(suspended_node_execution, execution, %{}, execution_context)
    params = suspended_node_execution.params || %{}

    case get_action(node) do
      {:ok, action} ->
        handle_resume_action(action, params, context, resume_data, suspended_node_execution, execution)

      {:error, reason} ->
        handle_resume_error(suspended_node_execution, reason)
    end
  end

  @spec prepare_params(Node.t(), map()) :: {:ok, map()} | {:error, term()}
  defp prepare_params(%Node{params: nil}, _context), do: {:ok, %{}}

  defp prepare_params(%Node{params: params}, context) when is_map(params) do
    case Prana.Template.process_map(params, context) do
      {:ok, processed_map} ->
        {:ok, processed_map || %{}}

      {:error, reason} ->
        {:error, build_params_error("expression_evaluation_failed", reason, params)}
    end
  rescue
    error ->
      {:error, build_params_error("params_preparation_failed", inspect(error), params)}
  end

  defp build_params_error(type, reason, params) do
    Error.new("params_error", reason, %{"error_type" => type, "params" => params})
  end

  # =============================================================================
  # ACTION MANAGEMENT
  # =============================================================================

  defp get_action(%Node{} = node) do
    case IntegrationRegistry.get_action_by_type(node.type) do
      {:ok, action} ->
        {:ok, action}

      {:error, :not_found} ->
        {:error, build_action_error("action_not_found", node.type)}

      {:error, reason} ->
        {:error, build_registry_error(reason)}
    end
  end

  defp build_action_error(type, action_name) do
    Error.new(type, "Action not found", %{"action_name" => action_name})
  end

  defp build_registry_error(reason) do
    Error.new("registry_error", "Registry error occurred", %{"reason" => reason})
  end

  # =============================================================================
  # ACTION INVOCATION
  # =============================================================================

  # Public for test purposes, but generally not used directly
  @spec invoke_action(Prana.Action.t(), map(), map()) :: {:ok, term(), String.t()} | {:error, term()}
  def invoke_action(%Prana.Action{} = action, input, context) do
    result = action.module.execute(input, context)
    process_action_result(result, action)
  rescue
    error ->
      {:error, build_action_execution_error("action_execution_failed", error, action)}
  catch
    :exit, reason ->
      {:error, build_action_execution_error("action_exit", reason, action)}

    :throw, value ->
      {:error, build_action_execution_error("action_throw", value, action)}
  end

  # Public for test purposes, but generally not used directly
  @spec invoke_resume_action(Prana.Action.t(), map(), map(), term()) :: {:ok, term(), String.t()} | {:error, term()}
  def invoke_resume_action(%Prana.Action{} = action, params, context, resume_data) do
    result = action.module.resume(params, context, resume_data)
    process_action_result(result, action)
  rescue
    error ->
      {:error, build_action_execution_error("action_resume_failed", error, action)}
  catch
    :exit, reason ->
      {:error, build_action_execution_error("action_resume_exit", reason, action)}

    :throw, value ->
      {:error, build_action_execution_error("action_resume_throw", value, action)}
  end

  defp build_action_execution_error(type, error_data, action) do
    Error.new(type, "Action execution failed", %{
      "details" => inspect(error_data),
      "module" => action.module,
      "action" => action.name
    })
  end

  # =============================================================================
  # RESULT PROCESSING
  # =============================================================================

  @doc """
  PUBLIC FOR TESTING

  Process different action return formats and determine output port.

  Supports suspension for sub-workflow orchestration and other async patterns.

  ## Supported Return Formats

  ### Standard Returns
  - `{:ok, data}` - Success with default success port
  - `{:error, error}` - Error with default error port
  - `{:ok, data, port}` - Success with explicit port selection
  - `{:error, error, port}` - Error with explicit port selection

  ### Context-Aware Returns
  - `{:ok, data, port, context}` - Success with port and context data
  - `{:ok, data, context}` - Success with context data (default port)

  ### Suspension Returns
  - `{:suspend, suspension_type, suspension_data}` - Pause execution for async coordination

  #### Built-in Suspension Types:
  - `:sub_workflow_sync` - Synchronous sub-workflow execution
  - `:sub_workflow_async` - Asynchronous sub-workflow execution
  - `:sub_workflow_fire_forget` - Fire-and-forget sub-workflow execution

  Custom suspension types are supported for domain-specific async patterns.

  ## Examples

      # Simple success
      {:ok, %{user_id: 123}}

      # Explicit port routing
      {:ok, result, "premium_path"}

      # Context-aware success (default port)
      {:ok, %{user_id: 123}, %{"batch_size" => 10, "has_more" => true}}

      # Context-aware with explicit port
      {:ok, result, "premium_path", %{"processing_time_ms" => 150}}

      # Sub-workflow suspension
      {:suspend, :sub_workflow_sync, %{
        workflow_id: "child_workflow",
        execution_mode: "sync",
        timeout_ms: 300_000
      }}

      # Custom suspension
      {:suspend, :approval_required, %{
        approval_id: "approval_123",
        approver_email: "manager@company.com"
      }}
  """
  @spec process_action_result(term(), Prana.Action.t()) ::
          {:ok, term(), String.t()} | {:ok, term(), String.t(), map()} | {:error, term()} | {:suspend, atom(), term()}
  def process_action_result(result, %Prana.Action{} = action) do
    case result do
      {:suspend, suspension_type, suspension_data} when is_atom(suspension_type) ->
        {:suspend, suspension_type, suspension_data}

      {:ok, data, port, state_updates} when is_binary(port) and is_map(state_updates) ->
        handle_success_with_port_and_state(data, port, state_updates, action)

      {:ok, data, state_updates} when is_map(state_updates) ->
        port = get_default_success_port(action)
        handle_success_with_port_and_state(data, port, state_updates, action)

      {:ok, data, port} when is_binary(port) ->
        handle_success_with_port(data, port, action)

      {:error, error, port} when is_binary(port) ->
        handle_error_with_port(error, port, action)

      {:ok, data} ->
        port = get_default_success_port(action)
        {:ok, data, port}

      {:error, error} ->
        port = get_default_error_port(action)
        {:error, build_action_error_result(error, port)}

      invalid_result ->
        {:error, build_invalid_format_error(invalid_result)}
    end
  end

  defp handle_success_with_port_and_state(data, port, state_updates, action) do
    if valid_port?(port, action) do
      {:ok, data, port, state_updates}
    else
      {:error, build_invalid_port_error(port, action)}
    end
  end

  defp handle_success_with_port(data, port, action) do
    if valid_port?(port, action) do
      {:ok, data, port}
    else
      {:error, build_invalid_port_error(port, action)}
    end
  end

  defp handle_error_with_port(error, port, action) do
    if valid_port?(port, action) do
      {:error, build_action_error_result(error, port)}
    else
      {:error, build_invalid_port_error(port, action)}
    end
  end

  defp valid_port?(port, action) do
    allows_dynamic_ports?(action) or port in action.output_ports
  end

  defp build_action_error_result(error, port) do
    Error.new("action_error", "Action returned error", %{
      "error" => error,
      "port" => port
    })
  end

  defp build_invalid_port_error(port, action) do
    Error.new("invalid_output_port", "Invalid output port specified", %{
      "port" => port,
      "available_ports" => action.output_ports
    })
  end

  defp build_invalid_format_error(invalid_result) do
    Error.new(
      "invalid_action_return_format",
      "Actions must return {:ok, data} | {:error, error} | {:ok, data, port} | {:error, error, port} | {:ok, data, context} | {:ok, data, port, context} | {:suspend, type, data}",
      %{"result" => inspect(invalid_result)}
    )
  end

  # =============================================================================
  # RETRY HELPERS
  # =============================================================================

  # Check if node should retry based on settings and current attempt
  defp should_retry?(node, node_execution, error_reason) do
    settings = node.settings
    current_attempt = get_current_attempt_number(node_execution)

    settings.retry_on_failed and settings.max_retries > 0 and current_attempt < settings.max_retries and
      is_retryable_error?(error_reason)
  end

  # Extract current attempt number from suspension_data (if this is a retry)
  defp get_current_attempt_number(node_execution) do
    if node_execution.suspension_type == :retry do
      node_execution.suspension_data["attempt_number"] || 0
    else
      # First attempt
      0
    end
  end

  # Get next attempt number
  defp get_next_attempt_number(node_execution) do
    get_current_attempt_number(node_execution) + 1
  end

  # Check if an error is retryable (only action execution errors should be retried)
  defp is_retryable_error?(%Error{code: code}) do
    case code do
      # ONLY action execution errors are retryable
      "action_error" -> true
      "action_execution_failed" -> true
      "action_exit" -> true
      "action_throw" -> true
      # All other errors are configuration/setup errors - NOT retryable
      _ -> false
    end
  end

  # Handle non-Error structs (shouldn't happen in normal flow, but be defensive)
  defp is_retryable_error?(_error), do: false

  # =============================================================================
  # EXECUTION HELPERS
  # =============================================================================

  defp create_node_execution(node, execution_index, run_index) do
    node.key
    |> NodeExecution.new(execution_index, run_index)
    |> NodeExecution.start()
  end

  defp handle_action_execution(node, action, prepared_params, context, node_execution, execution) do
    case invoke_action(action, prepared_params, context) do
      {:ok, output_data, output_port} ->
        completed_execution = NodeExecution.complete(node_execution, output_data, output_port)
        # Always return updated WorkflowExecution, even when no context updates
        updated_execution = Prana.WorkflowExecution.complete_node(execution, completed_execution)
        {:ok, completed_execution, updated_execution}

      {:ok, output_data, output_port, state_updates} ->
        # Extract node context updates from state_updates if present
        {node_context_updates, workflow_state_updates} = extract_node_context_updates(state_updates)

        completed_execution = NodeExecution.complete(node_execution, output_data, output_port)

        # Apply context updates to the WorkflowExecution
        updated_execution =
          complete_node_with_context_update(execution, completed_execution, node_context_updates, workflow_state_updates)

        {:ok, completed_execution, updated_execution}

      {:suspend, suspension_type, suspension_data} ->
        suspended_execution = NodeExecution.suspend(node_execution, suspension_type, suspension_data)
        {:suspend, suspended_execution}

      {:error, reason} ->
        handle_execution_error(node, node_execution, reason)
    end
  end

  defp handle_resume_action(action, params, context, resume_data, suspended_node_execution, execution) do
    resume_execution = NodeExecution.resume(suspended_node_execution)

    case invoke_resume_action(action, params, context, resume_data) do
      {:ok, output_data, output_port} ->
        completed_execution = NodeExecution.complete(resume_execution, output_data, output_port)
        # Always return updated WorkflowExecution, even when no context updates
        updated_execution = Prana.WorkflowExecution.complete_node(execution, completed_execution)
        {:ok, completed_execution, updated_execution}

      {:ok, output_data, output_port, state_updates} ->
        # Extract node context updates from state_updates if present
        {node_context_updates, workflow_state_updates} = extract_node_context_updates(state_updates)

        completed_execution = NodeExecution.complete(resume_execution, output_data, output_port)

        # Apply context updates to the WorkflowExecution
        updated_execution =
          complete_node_with_context_update(execution, completed_execution, node_context_updates, workflow_state_updates)

        {:ok, completed_execution, updated_execution}

      {:suspend, suspension_type, suspension_data} ->
        suspended_execution = NodeExecution.suspend(resume_execution, suspension_type, suspension_data)
        {:suspend, suspended_execution}

      {:error, reason} ->
        handle_resume_error(resume_execution, reason)
    end
  end

  # For execute failures - includes retry logic
  defp handle_execution_error(node, node_execution, reason) do
    if should_retry?(node, node_execution, reason) do
      # Prepare retry suspension data
      next_attempt = get_next_attempt_number(node_execution)

      retry_suspension_data = %{
        "resume_at" => DateTime.add(DateTime.utc_now(), node.settings.retry_delay_ms, :millisecond),
        "attempt_number" => next_attempt,
        "max_attempts" => node.settings.max_retries,
        "original_error" => reason
        # Note: No original_input stored - will be rebuilt on retry
      }

      # Suspend for retry
      suspended_execution = NodeExecution.suspend(node_execution, :retry, retry_suspension_data)
      {:suspend, suspended_execution}
    else
      # Normal failure path
      failed_execution = NodeExecution.fail(node_execution, reason)
      {:error, {reason, failed_execution}}
    end
  end

  # For resume failures - no retry logic
  defp handle_resume_error(node_execution, reason) do
    failed_execution = NodeExecution.fail(node_execution, reason)
    {:error, {reason, failed_execution}}
  end

  # =============================================================================
  # CONTEXT BUILDING
  # =============================================================================

  @spec build_expression_context(NodeExecution.t(), Prana.WorkflowExecution.t(), map(), map()) :: map()
  defp build_expression_context(node_execution, %Prana.WorkflowExecution{} = execution, routed_input, execution_context) do
    %{
      "$input" => routed_input,
      "$nodes" => execution.__runtime["nodes"],
      "$env" => execution.__runtime["env"],
      "$vars" => execution.vars,
      "$workflow" => %{
        "id" => execution.workflow_id,
        "version" => execution.workflow_version
      },
      "$execution" => %{
        "current_node_key" => node_execution.node_key,
        "run_index" => node_execution.run_index,
        "execution_index" => node_execution.execution_index,
        "id" => execution.id,
        "mode" => execution.execution_mode,
        "loopback" => get_in(execution_context, [:loop_metadata, :loopback]) || false,
        "loop" => Map.get(execution_context, :loop_metadata, %{}),
        "preparation" => execution.preparation_data,
        "state" => execution.execution_data["context_data"]["workflow"] || %{}
      },
      "$now" => DateTime.utc_now()
    }
  end

  # =============================================================================
  # PARAMETER PREPARATION
  # =============================================================================

  @spec get_default_success_port(Prana.Action.t()) :: String.t()
  defp get_default_success_port(%Prana.Action{output_ports: ports}) do
    cond do
      "main" in ports -> "main"
      length(ports) > 0 -> List.first(ports)
      true -> "main"
    end
  end

  @spec get_default_error_port(Prana.Action.t()) :: String.t()
  defp get_default_error_port(%Prana.Action{output_ports: ports}) do
    cond do
      "error" in ports -> "error"
      "failure" in ports -> "failure"
      true -> "error"
    end
  end

  defp allows_dynamic_ports?(%Prana.Action{output_ports: ["*"]}), do: true
  defp allows_dynamic_ports?(_action), do: false

  # Extract node context updates from state_updates map
  # Actions can use special key "node_context" to update current node's context
  defp extract_node_context_updates(state_updates) when is_map(state_updates) do
    case Map.pop(state_updates, "node_context") do
      {nil, remaining} ->
        {%{}, remaining}

      {node_context, remaining} when is_map(node_context) ->
        {node_context, remaining}

      {_invalid, remaining} ->
        {%{}, remaining}
    end
  end

  defp extract_node_context_updates(_), do: {%{}, %{}}

  # Apply context updates to WorkflowExecution and complete the node
  defp complete_node_with_context_update(
         execution,
         %{node_key: node_key} = completed_node_execution,
         node_context_updates,
         workflow_state_updates
       ) do
    execution
    |> Prana.WorkflowExecution.complete_node(completed_node_execution)
    |> then(fn exec ->
      # Apply node context updates if present
      if map_size(node_context_updates) > 0 do
        Prana.WorkflowExecution.update_node_context(exec, node_key, node_context_updates)
      else
        exec
      end
    end)
    |> then(fn exec ->
      # Apply workflow context updates if present
      if map_size(workflow_state_updates) > 0 do
        Prana.WorkflowExecution.update_execution_context(exec, workflow_state_updates)
      else
        exec
      end
    end)
  end
end
