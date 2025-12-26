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

  require Logger

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

    with {:ok, action} <- get_action(node),
         {:ok, prepared_params} <- prepare_params(node, action_context),
         {:ok, validated_params} <- validate_params(prepared_params, node, action) do
      node_execution = %{node_execution | params: validated_params}
      handle_action_execution(node, action, validated_params, action_context, node_execution, execution)
    else
      {:error, reason} ->
        handle_execution_error(node, node_execution, reason, execution)
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

    with {:ok, action} <- get_action(node),
         {:ok, prepared_params} <- prepare_params(node, action_context),
         {:ok, validated_params} <- validate_params(prepared_params, node, action) do
      node_execution = %{resumed_node_execution | params: validated_params}

      # Use unified handler with retry context for proper attempt tracking
      result = invoke_action(action, validated_params, action_context)
      handle_action_result(result, node, node_execution, execution, failed_node_execution)
    else
      {:error, reason} ->
        # For preparation failures, also handle with retry context
        handle_execution_error(node, resumed_node_execution, reason, execution, failed_node_execution)
    end
  end

  # Unified error handler for both initial execution and retry failures
  # Handles retry logic and respects on_error settings when retries are exhausted
  #
  # ## Parameters
  # - `node` - The node being executed
  # - `node_execution` - Current node execution state
  # - `reason` - The error that occurred
  # - `execution` - Current workflow execution (needed for error continuation)
  # - `original_failed_execution` - Original failed execution for retry scenarios (tracks attempt count)
  #
  # ## Returns
  # - `{:suspend, suspended_execution}` - Node suspended for retry
  # - `{:ok, completed_execution, updated_execution}` - Error handled with continuation
  # - `{:error, {reason, failed_execution}}` - Final failure
  defp handle_execution_error(node, node_execution, reason, execution, original_failed_execution \\ nil) do
    # Get current attempt number from original failure context (for retries) or current execution
    current_attempt = get_current_attempt_number(original_failed_execution || node_execution)

    if should_retry_with_attempt?(node, current_attempt, reason) do
      # Prepare retry suspension data with incremented attempt
      next_attempt = current_attempt + 1

      retry_suspension_data = %{
        "resume_at" => DateTime.add(DateTime.utc_now(), node.settings.retry_delay_ms, :millisecond),
        "attempt_number" => next_attempt,
        "max_attempts" => node.settings.max_retries,
        "original_error" => reason
      }

      # Suspend for retry
      suspended_execution = NodeExecution.suspend(node_execution, :retry, retry_suspension_data)
      {:suspend, suspended_execution}
    else
      # No more retries - check on_error setting to determine final behavior
      case node.settings.on_error do
        "stop_workflow" ->
          # Current behavior - fail workflow
          failed_execution = NodeExecution.fail(node_execution, reason)
          {:error, {reason, failed_execution}}

        "continue" ->
          # Continue with error through default output port
          handle_error_continuation(node, node_execution, reason, :default_port, execution)

        "continue_error_output" ->
          # Continue with error through virtual "error" port
          handle_error_continuation(node, node_execution, reason, :error_port, execution)
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

    with {:ok, action} <- get_action(node),
         {:ok, validated_params} <- validate_params(params, node, action) do
      handle_resume_action(action, validated_params, context, resume_data, suspended_node_execution, execution)
    else
      {:error, reason} ->
        handle_resume_error(suspended_node_execution, reason)
    end
  end

  @spec prepare_params(Node.t(), map()) :: {:ok, map()} | {:error, term()}
  defp prepare_params(%Node{params: nil}, _context), do: {:ok, %{}}

  defp prepare_params(%Node{params: params} = node, context) when is_map(params) do
    case Prana.Template.process_map(params, context) do
      {:ok, processed_map} ->
        {:ok, processed_map || %{}}

      {:error, reason} ->
        {:error,
         Error.engine_error("Failed to process action's params", %{
           reason: reason,
           params: params,
           node: node.key,
           action: node.type
         })}
    end
  rescue
    error ->
      Prana.ErrorTracker.capture_error(error, __STACKTRACE__)
      {:error,
       Error.engine_error("Failed to process action's params", %{
         reason: error,
         params: params,
         node: node.key,
         action: node.type
       })}
  end

  @spec validate_params(map(), Node.t(), Prana.Action.t()) :: {:ok, map()} | {:error, term()}
  defp validate_params(params, _node, %Prana.Action{params_schema: nil}), do: {:ok, params}

  defp validate_params(params, node, %Prana.Action{params_schema: schema} = action) when is_map(schema) do
    case Skema.cast(params, schema) do
      {:ok, validated_params} ->
        {:ok, validated_params}

      {:error, errors} ->
        {:error,
         Error.workflow_error("Action parameters validation failed", %{
           code: "workflow.invalid_action_params",
           node: node.key,
           action: action.name,
           reason: errors.errors
         })}
    end
  end

  # =============================================================================
  # ACTION MANAGEMENT
  # =============================================================================

  defp get_action(%Node{} = node) do
    case IntegrationRegistry.get_action_by_type(node.type) do
      {:ok, action} ->
        {:ok, action}

      {:error, :not_found} ->
        {:error, Error.new("action.not_found", "Action not found", %{node: node.key, action: node.type})}

      {:error, reason} ->
        {:error, Error.engine_error("Registry error occurred", %{reason: reason, node: node.key, action: node.type})}
    end
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
      Prana.ErrorTracker.capture_error(error, __STACKTRACE__)
      stacktrace = Exception.format_stacktrace(__STACKTRACE__)

      {:error,
       Error.new("action.exception", "Action execution exception", %{
         details: error,
         stacktrace: stacktrace
       })}
  end

  # Public for test purposes, but generally not used directly
  @spec invoke_resume_action(Prana.Action.t(), map(), map(), term()) :: {:ok, term(), String.t()} | {:error, term()}
  def invoke_resume_action(%Prana.Action{} = action, params, context, resume_data) do
    result = action.module.resume(params, context, resume_data)
    process_action_result(result, action)
  rescue
    error ->
      Prana.ErrorTracker.capture_error(error, __STACKTRACE__)
      stacktrace = Exception.format_stacktrace(__STACKTRACE__)

      {:error,
       Error.new("action.exception", "Action execution exception", %{
         details: error,
         stacktrace: stacktrace
       })}
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

      {:ok, data} ->
        port = get_default_success_port(action)
        {:ok, data, port}

      {:error, error} ->
        {:error, error}

      _invalid_result ->
        {:error,
         Error.new(
           "action.invalid_return",
           "Actions must return {:ok, data} | {:error, error} | {:ok, data, port} | {:error, error, port} | {:ok, data, context} | {:ok, data, port, context} | {:suspend, type, data}",
           %{action: action.name}
         )}
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

  defp valid_port?(port, action) do
    allows_dynamic_ports?(action) or port in action.output_ports
  end

  defp build_invalid_port_error(port, action) do
    Error.new("action.invalid_output_port", "Invalid output port specified", %{
      action: action.name,
      invalid_port: port
    })
  end

  # =============================================================================
  # RETRY HELPERS
  # =============================================================================

  # Extract current attempt number from suspension_data (if this is a retry)
  defp get_current_attempt_number(node_execution) do
    if node_execution.suspension_type == :retry do
      node_execution.suspension_data["attempt_number"] || 0
    else
      # First attempt
      0
    end
  end

  # Check if an error is retryable (only action execution errors should be retried)
  defp is_retryable_error?(%Error{code: "action.execution_error"}), do: true

  defp is_retryable_error?(_error), do: false

  # =============================================================================
  # EXECUTION HELPERS
  # =============================================================================

  defp create_node_execution(node, execution_index, run_index) do
    node.key
    |> NodeExecution.new(execution_index, run_index)
    |> NodeExecution.start()
  end

  # Unified action result handler for execute, retry, and resume operations
  # Handles all action result patterns consistently
  #
  # ## Parameters
  # - `result` - Result from invoke_action or invoke_resume_action
  # - `node` - The node being executed (nil for resume operations without retry support)
  # - `node_execution` - Current node execution state
  # - `execution` - Current workflow execution
  # - `original_failed_execution` - Original failed execution for retry tracking (nil for non-retry)
  #
  # ## Returns
  # - `{:ok, completed_execution, updated_execution}` - Success
  # - `{:suspend, suspended_execution}` - Node suspended
  # - `{:error, {reason, failed_execution}}` - Error with failed execution
  defp handle_action_result(result, node, node_execution, execution, original_failed_execution \\ nil) do
    case result do
      {:ok, output_data, output_port} ->
        completed_execution = NodeExecution.complete(node_execution, output_data, output_port)
        updated_execution = Prana.WorkflowExecution.complete_node(execution, completed_execution)
        {:ok, completed_execution, updated_execution}

      {:ok, output_data, output_port, state_updates} ->
        {node_context_updates, workflow_state_updates} = extract_node_context_updates(state_updates)
        completed_execution = NodeExecution.complete(node_execution, output_data, output_port)

        updated_execution =
          complete_node_with_context_update(execution, completed_execution, node_context_updates, workflow_state_updates)

        {:ok, completed_execution, updated_execution}

      {:suspend, suspension_type, suspension_data} ->
        suspended_execution = NodeExecution.suspend(node_execution, suspension_type, suspension_data)
        {:suspend, suspended_execution}

      {:error, reason} ->
        # Wrap error for consistent error handling
        details =
          reason
          |> Error.to_map()
          |> Map.merge(%{
            action: node && node.type,
            node: node_execution.node_key
          })

        error =
          Error.new(
            "action.execution_error",
            "Node execution failed",
            details
          )

        if node do
          # execute_node or retry_node - support retry and on_error settings
          handle_execution_error(node, node_execution, error, execution, original_failed_execution)
        else
          # resume_node - no retry support
          handle_resume_error(node_execution, error)
        end
    end
  end

  defp handle_action_execution(node, action, prepared_params, context, node_execution, execution) do
    result = invoke_action(action, prepared_params, context)
    handle_action_result(result, node, node_execution, execution)
  end

  defp handle_resume_action(action, params, context, resume_data, suspended_node_execution, execution) do
    resume_execution = NodeExecution.resume(suspended_node_execution)
    result = invoke_resume_action(action, params, context, resume_data)
    # Pass nil for node to indicate no retry support
    handle_action_result(result, nil, resume_execution, execution)
  end

  # Handle error continuation based on on_error setting
  # This function is called from handle_execution_error, which is only used by execute_node
  # We need to also return the updated WorkflowExecution for GraphExecutor compatibility
  defp handle_error_continuation(node, node_execution, reason, port_type, execution) do
    # Determine the output port based on port_type
    output_port =
      case port_type do
        :default_port ->
          # Get the action to determine default success port
          case IntegrationRegistry.get_action_by_type(node.type) do
            {:ok, action} -> get_default_success_port(action)
            # fallback
            {:error, _} -> "main"
          end

        :error_port ->
          # Virtual error port
          "error"
      end

    # Extract the original error information from the Error struct
    {original_error, original_port} =
      case reason do
        %Error{details: %{details: _} = error} ->
          {error, output_port}

        error ->
          {error, output_port}
      end

    # Create error data with port information
    error_data =
      Error.new("action_error", "Action returned error", %{
        error: original_error,
        port: original_port,
        on_error_behavior: Atom.to_string(port_type)
      })

    # Complete the node execution successfully with error data
    completed_execution = NodeExecution.complete(node_execution, error_data, output_port)
    updated_execution = Prana.WorkflowExecution.complete_node(execution, completed_execution)
    {:ok, completed_execution, updated_execution}
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
