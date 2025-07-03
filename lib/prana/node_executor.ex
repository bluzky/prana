defmodule Prana.NodeExecutor do
  @moduledoc """
  Executes individual nodes within a workflow.

  Handles:
  - Expression-based input preparation using ExpressionEngine
  - Action invocation via MFA pattern
  - Output processing and port determination
  - Basic error handling
  """

  alias Prana.ExecutionContext
  alias Prana.ExpressionEngine
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecution

  @doc """
  Execute a single node with the given context.

  ## Parameters
  - `node` - The node to execute
  - `context` - Current execution context

  ## Returns
  - `{:ok, node_execution, updated_context}` - Successful execution
  - `{:suspend, node_execution}` - Node suspended for async coordination
  - `{:error, reason}` - Execution failed
  """
  @spec execute_node(Node.t(), ExecutionContext.t()) ::
          {:ok, NodeExecution.t(), ExecutionContext.t()}
          | {:suspend, NodeExecution.t()}
          | {:error, term()}
  def execute_node(%Node{} = node, %ExecutionContext{} = context) do
    # Create initial node execution with proper execution ID from context
    node_execution = NodeExecution.new(context.execution_id, node.id, %{})
    node_execution = NodeExecution.start(node_execution)

    with {:ok, prepared_input} <- prepare_input(node, context),
         {:ok, action} <-
           get_action(node) do
      case invoke_action(action, prepared_input) do
        {:ok, output_data, output_port} ->
          # Successful execution - complete the node
          updated_context = update_context(context, node, output_data)

          completed_execution = NodeExecution.complete(node_execution, output_data, output_port)
          {:ok, completed_execution, updated_context}

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
        # Input preparation or action retrieval failed
        failed_execution = NodeExecution.fail(node_execution, reason)
        {:error, {reason, failed_execution}}
    end
  end

  @doc """
  Resume a suspended node execution with resume data.

  ## Parameters
  - `node` - The node definition
  - `context` - Current execution context
  - `suspended_node_execution` - The suspended NodeExecution to resume
  - `resume_data` - Data to complete the suspended execution with

  ## Returns
  - `{:ok, node_execution, updated_context}` - Successfully resumed and completed
  - `{:error, {reason, failed_node_execution}}` - Resume failed
  """
  @spec resume_node(Node.t(), ExecutionContext.t(), NodeExecution.t(), map()) ::
          {:ok, NodeExecution.t(), ExecutionContext.t()}
  def resume_node(%Node{} = node, %ExecutionContext{} = context, %NodeExecution{} = suspended_node_execution, resume_data) do
    # Extract actual output data from resume data structure
    # For sub-workflows, resume_data contains metadata alongside the actual output
    output_data =
      case resume_data do
        %{"sub_workflow_output" => output} -> output
        # Use full resume data if no sub_workflow_output key
        _ -> resume_data
      end

    updated_context = update_context(context, node, output_data)

    completed_execution = NodeExecution.complete(suspended_node_execution, output_data, "success")
    {:ok, completed_execution, updated_context}
  end

  @doc """
  Prepare node input by evaluating expressions in input_map against context.
  """
  @spec prepare_input(Node.t(), ExecutionContext.t()) :: {:ok, map()} | {:error, term()}
  def prepare_input(%Node{input_map: input_map}, %ExecutionContext{} = context) do
    # Handle nil input_map by providing empty map
    actual_input_map = input_map || %{}
    context_data = build_expression_context(context)

    try do
      case ExpressionEngine.process_map(actual_input_map, context_data) do
        {:ok, processed_map} ->
          # Enrich input with full context access using prefixed keys to avoid conflicts
          context_with_prefixed_keys = %{
            "$input" => context_data["$input"],
            "$nodes" => context_data["$nodes"],
            "$variables" => context_data["$variables"],
            "$preparation" => context_data["$preparation"]
          }

          enriched_input = Map.merge(processed_map || %{}, context_with_prefixed_keys)
          {:ok, enriched_input}

        {:error, reason} ->
          {:error,
           %{
             "type" => "expression_evaluation_failed",
             "reason" => reason,
             "input_map" => input_map
           }}
      end
    rescue
      error ->
        {:error,
         %{
           "type" => "input_preparation_failed",
           "error" => inspect(error),
           "input_map" => input_map
         }}
    end
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
  @spec invoke_action(Prana.Action.t(), map()) :: {:ok, term(), String.t()} | {:error, term()}
  def invoke_action(%Prana.Action{} = action, input) do
    result = if action.function do
      # Old MFA pattern (for backward compatibility)
      apply(action.module, action.function, [input])
    else
      # New Action behavior pattern
      action.module.execute(input)
    end
    process_action_result(result, action)
  rescue
    error ->
      {:error,
       %{
         "type" => "action_execution_failed",
         "error" => inspect(error),
         "module" => action.module,
         "function" => action.function
       }}
  catch
    :exit, reason ->
      {:error,
       %{
         "type" => "action_exit",
         "reason" => inspect(reason),
         "module" => action.module,
         "function" => action.function
       }}

    :throw, value ->
      {:error,
       %{
         "type" => "action_throw",
         "value" => inspect(value),
         "module" => action.module,
         "function" => action.function
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

      # Sub-workflow suspension
      {:suspend, :sub_workflow_sync, %{
        workflow_id: "child_workflow",
        input_data: %{"user_id" => 123},
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
          {:ok, term(), String.t()} | {:error, term()} | {:suspend, atom(), term()}
  def process_action_result(result, %Prana.Action{} = action) do
    case result do
      # Suspension format for async coordination: {:suspend, type, data}
      {:suspend, suspension_type, suspend_data} when is_atom(suspension_type) ->
        {:suspend, suspension_type, suspend_data}

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
        port = action.default_success_port || get_default_success_port(action)
        {:ok, data, port}

      # Default error format: {:error, error}
      {:error, error} ->
        port = action.default_error_port || get_default_error_port(action)

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
             "Actions must return {:ok, data} | {:error, error} | {:ok, data, port} | {:error, error, port} | {:suspend, type, data}"
         }}
    end
  end

  @doc """
  Update execution context with node results.
  """
  @spec update_context(ExecutionContext.t(), Node.t(), term()) ::
          ExecutionContext.t()
  def update_context(%ExecutionContext{} = context, %Node{} = node, output_data) do
    # Store result only under node.custom_id for flexible access
    nodes = Map.put(context.nodes, node.custom_id, output_data)
    %{context | nodes: nodes}
  end

  # Private helper functions

  @spec build_expression_context(ExecutionContext.t()) :: map()
  defp build_expression_context(%ExecutionContext{} = context) do
    preparation_data = case context.execution do
      nil -> %{}
      execution -> execution.preparation_data || %{}
    end
    
    %{
      "$input" => context.input,
      "$nodes" => context.nodes,
      "$variables" => context.variables,
      "$preparation" => preparation_data
    }
  end

  @spec get_default_success_port(Prana.Action.t()) :: String.t()
  defp get_default_success_port(%Prana.Action{output_ports: ports}) do
    cond do
      "success" in ports -> "success"
      "output" in ports -> "output"
      length(ports) > 0 -> List.first(ports)
      # fallback
      true -> "success"
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
