defmodule Prana.NodeExecutor do
  @moduledoc """
  Executes individual nodes within a workflow.

  Handles:
  - Expression-based input preparation using ExpressionEngine
  - Action invocation via MFA pattern
  - Output processing and port determination
  - Basic error handling
  """

  alias Prana.ExpressionEngine
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecution

  @doc """
  Execute a single node with the given execution and routed input.

  ## Parameters
  - `node` - The node to execute
  - `execution` - Current execution state (with __runtime initialized)
  - `routed_input` - Input data routed to this node's input ports

  ## Returns
  - `{:ok, node_execution, updated_execution}` - Successful execution
  - `{:suspend, node_execution}` - Node suspended for async coordination
  - `{:error, reason}` - Execution failed
  """
  @spec execute_node(Node.t(), Prana.Execution.t(), map()) ::
          {:ok, NodeExecution.t(), Prana.Execution.t()}
          | {:suspend, NodeExecution.t()}
          | {:error, term()}
  def execute_node(%Node{} = node, %Prana.Execution{} = execution, routed_input) do
    # Create initial node execution with proper execution ID from execution
    node_execution =
      execution.id
      |> NodeExecution.new(node.id)
      |> NodeExecution.start()

    # Build context once for both input preparation and action execution
    context = build_expression_context(execution, routed_input)

    with {:ok, prepared_params} <- prepare_params(node, context),
         {:ok, action} <- get_action(node) do
      node_execution = %{node_execution | params: prepared_params}

      case invoke_action(action, prepared_params, context) do
        {:ok, output_data, output_port, context} ->
          # Complete the local node execution and update context
          completed_execution =
            node_execution
            |> NodeExecution.complete(output_data, output_port)
            |> NodeExecution.update_context(context)

          # Then integrate it into the execution state
          updated_execution = Prana.Execution.complete_node(execution, completed_execution)

          {:ok, completed_execution, updated_execution}

        {:ok, output_data, output_port} ->
          # Complete the local node execution without context data
          completed_execution = NodeExecution.complete(node_execution, output_data, output_port)

          # Then integrate it into the execution state
          updated_execution = Prana.Execution.complete_node(execution, completed_execution)

          {:ok, completed_execution, updated_execution}

        {:suspend, suspension_type, suspend_data} ->
          # Node suspended for async coordination
          suspended_execution = suspend_node_execution(node_execution, suspension_type, suspend_data)
          {:suspend, suspended_execution}

        {:error, reason} ->
          # Action execution failed
          failed_execution = NodeExecution.fail(node_execution, reason)
          {:error, {reason, failed_execution}}
      end
    else
      {:error, reason} ->
        # Params preparation or action retrieval failed
        failed_execution = NodeExecution.fail(node_execution, reason)
        {:error, {reason, failed_execution}}
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
  - `{:ok, node_execution, updated_execution}` - Successfully resumed and completed
  - `{:error, {reason, failed_node_execution}}` - Resume failed
  """
  @spec resume_node(Node.t(), Prana.Execution.t(), NodeExecution.t(), map()) ::
          {:ok, NodeExecution.t(), Prana.Execution.t()} | {:error, {term(), NodeExecution.t()}}
  def resume_node(
        %Node{} = node,
        %Prana.Execution{} = execution,
        %NodeExecution{} = suspended_node_execution,
        resume_data
      ) do
    # Build context for resume (same as execute_node)
    context = build_expression_context(execution, %{})

    # Get the original params from the suspended node execution
    params = suspended_node_execution.params || %{}

    case get_action(node) do
      {:ok, action} ->
        case invoke_resume_action(action, params, context, resume_data) do
          {:ok, output_data, output_port} ->
            # Complete the suspended node execution
            completed_execution = NodeExecution.complete(suspended_node_execution, output_data, output_port)

            # Integrate it into the execution state
            updated_execution = Prana.Execution.complete_node(execution, completed_execution)

            {:ok, completed_execution, updated_execution}

          {:ok, output_data, output_port, context} ->
            # Complete with context data
            completed_execution =
              suspended_node_execution
              |> NodeExecution.complete(output_data, output_port)
              |> NodeExecution.update_context(context)

            # Integrate it into the execution state
            updated_execution = Prana.Execution.complete_node(execution, completed_execution)

            {:ok, completed_execution, updated_execution}

          {:error, reason} ->
            # Resume failed
            failed_execution = NodeExecution.fail(suspended_node_execution, reason)
            {:error, {reason, failed_execution}}
        end

      {:error, reason} ->
        # Action retrieval failed
        failed_execution = NodeExecution.fail(suspended_node_execution, reason)
        {:error, {reason, failed_execution}}
    end
  end

  @doc """
  Prepare node params using expression evaluation.

  ## Parameters
  - `node` - The node to prepare params for
  - `context` - Full execution context for expression evaluation

  ## Returns
  - `{:ok, prepared_params}` - Params ready for action execution
  - `{:error, reason}` - Params preparation failed
  """
  @spec prepare_params(Node.t(), map()) :: {:ok, map()} | {:error, term()}
  def prepare_params(%Node{params: nil}, _context) do
    # No params defined - return empty map
    {:ok, %{}}
  end

  # Evaluate params expressions using context
  def prepare_params(%Node{params: params}, context) when is_map(params) do
    case ExpressionEngine.process_map(params, context) do
      {:ok, processed_map} ->
        {:ok, processed_map || %{}}

      {:error, reason} ->
        {:error,
         %{
           "type" => "expression_evaluation_failed",
           "reason" => reason,
           "params" => params
         }}
    end
  rescue
    error ->
      {:error,
       %{
         "type" => "params_preparation_failed",
         "error" => inspect(error),
         "params" => params
       }}
  end

  @doc """
  Get action definition from integration registry.
  """
  @spec get_action(Node.t()) :: {:ok, Prana.Action.t()} | {:error, term()}
  def get_action(%Node{integration_name: integration_name, action_name: action_name}) do
    case IntegrationRegistry.get_action(integration_name, action_name) do
      {:ok, action} ->
        {:ok, action}

      {:error, :not_found} ->
        {:error,
         %{
           "type" => "action_not_found",
           "integration_name" => integration_name,
           "action_name" => action_name
         }}

      {:error, reason} ->
        {:error,
         %{
           "type" => "registry_error",
           "reason" => reason
         }}
    end
  end

  @doc """
  Invoke action using Action behavior pattern and handle different return formats.
  """
  @spec invoke_action(Prana.Action.t(), map(), map()) :: {:ok, term(), String.t()} | {:error, term()}
  def invoke_action(%Prana.Action{} = action, input, context) do
    # Action behavior pattern with full context access
    result = action.module.execute(input, context)
    process_action_result(result, action)
  rescue
    error ->
      {:error,
       %{
         "type" => "action_execution_failed",
         "error" => inspect(error),
         "module" => action.module,
         "action" => action.name
       }}
  catch
    :exit, reason ->
      {:error,
       %{
         "type" => "action_exit",
         "reason" => inspect(reason),
         "module" => action.module,
         "action" => action.name
       }}

    :throw, value ->
      {:error,
       %{
         "type" => "action_throw",
         "value" => inspect(value),
         "module" => action.module,
         "action" => action.name
       }}
  end

  @doc """
  Invoke action resume method with params, context, and resume data.
  """
  @spec invoke_resume_action(Prana.Action.t(), map(), map(), term()) :: {:ok, term(), String.t()} | {:error, term()}
  def invoke_resume_action(%Prana.Action{} = action, params, context, resume_data) do
    # Call the action's resume method
    result = action.module.resume(params, context, resume_data)
    process_action_result(result, action)
  rescue
    error ->
      {:error,
       %{
         "type" => "action_resume_failed",
         "error" => inspect(error),
         "module" => action.module,
         "action" => action.name
       }}
  catch
    :exit, reason ->
      {:error,
       %{
         "type" => "action_resume_exit",
         "reason" => inspect(reason),
         "module" => action.module,
         "action" => action.name
       }}

    :throw, value ->
      {:error,
       %{
         "type" => "action_resume_throw",
         "value" => inspect(value),
         "module" => action.module,
         "action" => action.name
       }}
  end

  @doc """
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
  - `{:suspend, suspension_type, suspend_data}` - Pause execution for async coordination

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
      # Suspension format for async coordination: {:suspend, type, data}
      {:suspend, suspension_type, suspend_data} when is_atom(suspension_type) ->
        {:suspend, suspension_type, suspend_data}

      # Context-aware explicit port format: {:ok, data, port, context}
      {:ok, data, port, context} when is_binary(port) and is_map(context) ->
        if allows_dynamic_ports?(action) or port in action.output_ports do
          {:ok, data, port, context}
        else
          {:error,
           %{
             "type" => "invalid_output_port",
             "port" => port,
             "available_ports" => action.output_ports
           }}
        end

      # Context-aware default port format: {:ok, data, context}
      {:ok, data, context} when is_map(context) ->
        port = action.default_success_port || get_default_success_port(action)
        {:ok, data, port, context}

      # Explicit port format: {:ok, data, port}
      {:ok, data, port} when is_binary(port) ->
        if allows_dynamic_ports?(action) or port in action.output_ports do
          {:ok, data, port}
        else
          {:error,
           %{
             "type" => "invalid_output_port",
             "port" => port,
             "available_ports" => action.output_ports
           }}
        end

      # Explicit error with port: {:error, error, port}
      {:error, error, port} when is_binary(port) ->
        if allows_dynamic_ports?(action) or port in action.output_ports do
          {:error,
           %{
             "type" => "action_error",
             "error" => error,
             "port" => port
           }}
        else
          {:error,
           %{
             "type" => "invalid_output_port",
             "port" => port,
             "available_ports" => action.output_ports
           }}
        end

      # Default success format: {:ok, data}
      {:ok, data} ->
        port = get_default_success_port(action)
        {:ok, data, port}

      # Default error format: {:error, error}
      {:error, error} ->
        port = get_default_error_port(action)

        {:error,
         %{
           "type" => "action_error",
           "error" => error,
           "port" => port
         }}

      # Invalid format - all actions must return tuples
      invalid_result ->
        {:error,
         %{
           "type" => "invalid_action_return_format",
           "result" => inspect(invalid_result),
           "message" =>
             "Actions must return {:ok, data} | {:error, error} | {:ok, data, port} | {:error, error, port} | {:ok, data, context} | {:ok, data, port, context} | {:suspend, type, data}"
         }}
    end
  end

  # Private helper functions

  @spec build_expression_context(Prana.Execution.t(), map()) :: map()
  defp build_expression_context(%Prana.Execution{} = execution, routed_input) do
    # Build standardized expression context with all built-in variables
    %{
      # routed input by port
      "$input" => routed_input,
      # structured node data (output + context)
      "$nodes" => execution.__runtime["nodes"],
      # environment variables
      "$env" => execution.__runtime["env"],
      # workflow variables
      "$vars" => execution.vars,
      # workflow metadata
      "$workflow" => %{
        "id" => execution.workflow_id,
        "version" => execution.workflow_version
      },
      # execution metadata
      "$execution" => %{
        "id" => execution.id,
        "mode" => execution.execution_mode,
        "preparation" => execution.preparation_data
      }
    }
  end

  @spec get_default_success_port(Prana.Action.t()) :: String.t()
  defp get_default_success_port(%Prana.Action{output_ports: ports}) do
    cond do
      "output" in ports -> "output"
      length(ports) > 0 -> List.first(ports)
      # fallback
      true -> "output"
    end
  end

  @spec get_default_error_port(Prana.Action.t()) :: String.t()
  defp get_default_error_port(%Prana.Action{output_ports: ports}) do
    cond do
      "error" in ports -> "error"
      "failure" in ports -> "failure"
      length(ports) > 1 -> List.last(ports)
      # fallback
      true -> "error"
    end
  end

  # Check if action allows dynamic output ports
  defp allows_dynamic_ports?(%Prana.Action{output_ports: ["*"]}), do: true
  defp allows_dynamic_ports?(_action), do: false

  # Suspend node execution for async coordination
  defp suspend_node_execution(%NodeExecution{} = node_execution, suspension_type, suspend_data) do
    %{
      node_execution
      | status: :suspended,
        output_data: nil,
        output_port: nil,
        completed_at: nil,
        duration_ms: nil,
        suspension_type: suspension_type,
        suspension_data: suspend_data
    }
  end
end
