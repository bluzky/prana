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
  - `{:ok, node_execution}` - Successful execution
  - `{:ok, node_execution, shared_state_updates}` - Successful execution with shared state updates
  - `{:suspend, node_execution}` - Node suspended for async coordination
  - `{:error, reason}` - Execution failed
  """
  @spec execute_node(Node.t(), Prana.WorkflowExecution.t(), map(), integer(), integer()) ::
          {:ok, NodeExecution.t()}
          | {:ok, NodeExecution.t(), map()}
          | {:suspend, NodeExecution.t()}
          | {:error, term()}
  def execute_node(
        %Node{} = node,
        %Prana.WorkflowExecution{} = execution,
        routed_input,
        execution_index \\ 0,
        run_index \\ 0
      ) do
    node_execution = create_node_execution(node, execution_index, run_index)
    context = build_expression_context(node_execution, execution, routed_input)

    with {:ok, prepared_params} <- prepare_params(node, context),
         {:ok, action} <- get_action(node) do
      node_execution = %{node_execution | params: prepared_params}
      handle_action_execution(action, prepared_params, context, node_execution)
    else
      {:error, reason} ->
        handle_execution_error(node_execution, reason)
    end
  end

  @doc """
  Resume a suspended node execution with resume data.

  ## Parameters
  - `node` - The node definition
  - `execution` - Current execution state (with __runtime initialized)
  - `suspended_node_execution` - The suspended NodeExecution to resume
  - `resume_data` - Data to complete the suspended execution with

  ## Returns
  - `{:ok, node_execution}` - Successfully resumed and completed
  - `{:error, {reason, failed_node_execution}}` - Resume failed
  """
  @spec resume_node(Node.t(), Prana.WorkflowExecution.t(), NodeExecution.t(), map()) ::
          {:ok, NodeExecution.t()} | {:error, {term(), NodeExecution.t()}}
  def resume_node(
        %Node{} = node,
        %Prana.WorkflowExecution{} = execution,
        %NodeExecution{} = suspended_node_execution,
        resume_data
      ) do
    context = build_expression_context(suspended_node_execution, execution, %{})
    params = suspended_node_execution.params || %{}

    case get_action(node) do
      {:ok, action} ->
        handle_resume_action(action, params, context, resume_data, suspended_node_execution)

      {:error, reason} ->
        handle_execution_error(suspended_node_execution, reason)
    end
  end

  @spec prepare_params(Node.t(), map()) :: {:ok, map()} | {:error, term()}
  defp prepare_params(%Node{params: nil}, _context), do: {:ok, %{}}

  defp prepare_params(%Node{params: params}, context) when is_map(params) do
    case Prana.Template.Engine.process_map(params, context) do
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
  # EXECUTION HELPERS
  # =============================================================================

  defp create_node_execution(node, execution_index, run_index) do
    node.key
    |> NodeExecution.new(execution_index, run_index)
    |> NodeExecution.start()
  end

  defp handle_action_execution(action, prepared_params, context, node_execution) do
    case invoke_action(action, prepared_params, context) do
      {:ok, output_data, output_port} ->
        completed_execution = NodeExecution.complete(node_execution, output_data, output_port)
        {:ok, completed_execution}

      {:ok, output_data, output_port, state_updates} ->
        completed_execution = NodeExecution.complete(node_execution, output_data, output_port)
        # state_updates is the state map directly
        if map_size(state_updates) > 0 do
          {:ok, completed_execution, state_updates}
        else
          {:ok, completed_execution}
        end

      {:suspend, suspension_type, suspension_data} ->
        suspended_execution = NodeExecution.suspend(node_execution, suspension_type, suspension_data)
        {:suspend, suspended_execution}

      {:error, reason} ->
        handle_execution_error(node_execution, reason)
    end
  end

  defp handle_resume_action(action, params, context, resume_data, suspended_node_execution) do
    resume_execution = NodeExecution.resume(suspended_node_execution)

    case invoke_resume_action(action, params, context, resume_data) do
      {:ok, output_data, output_port} ->
        completed_execution = NodeExecution.complete(resume_execution, output_data, output_port)
        {:ok, completed_execution}

      {:ok, output_data, output_port, _context} ->
        completed_execution = NodeExecution.complete(resume_execution, output_data, output_port)
        {:ok, completed_execution}

      {:suspend, suspension_type, suspension_data} ->
        suspended_execution = NodeExecution.suspend(resume_execution, suspension_type, suspension_data)
        {:suspend, suspended_execution}

      {:error, reason} ->
        handle_execution_error(resume_execution, reason)
    end
  end

  defp handle_execution_error(node_execution, reason) do
    failed_execution = NodeExecution.fail(node_execution, reason)
    {:error, {reason, failed_execution}}
  end

  # =============================================================================
  # CONTEXT BUILDING
  # =============================================================================

  @spec build_expression_context(NodeExecution.t(), Prana.WorkflowExecution.t(), map()) :: map()
  defp build_expression_context(node_execution, %Prana.WorkflowExecution{} = execution, routed_input) do
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
        "preparation" => execution.preparation_data,
        "state" => execution.__runtime["shared_state"] || %{},
        "now" => DateTime.utc_now(),
      }
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
end
