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
  - `opts` - Execution options (currently unused)

  ## Returns
  - `{:ok, node_execution, updated_context}` - Successful execution
  - `{:error, reason}` - Execution failed
  """
  @spec execute_node(Node.t(), ExecutionContext.t(), keyword()) ::
          {:ok, NodeExecution.t(), ExecutionContext.t()} | {:error, term()}
  def execute_node(%Node{} = node, %ExecutionContext{} = context, _opts \\ []) do
    # Create initial node execution with proper execution ID from context
    node_execution = NodeExecution.new(context.execution_id, node.id, %{})
    node_execution = NodeExecution.start(node_execution)

    with {:ok, prepared_input} <- prepare_input(node, context),
         {:ok, action} <- get_action(node),
         {:ok, output_data, output_port} <- invoke_action(action, prepared_input),
         {:ok, updated_context} <- update_context(context, node, output_data) do
      # Complete successful execution
      completed_execution = NodeExecution.complete(node_execution, output_data, output_port)
      {:ok, completed_execution, updated_context}
    else
      {:error, reason} ->
        # Handle failed execution
        failed_execution = NodeExecution.fail(node_execution, reason)
        {:error, {reason, failed_execution}}
    end
  end

  @doc """
  Prepare node input by evaluating expressions in input_map against context.
  """
  @spec prepare_input(Node.t(), ExecutionContext.t()) :: {:ok, map()} | {:error, term()}
  def prepare_input(%Node{input_map: input_map}, %ExecutionContext{} = context) do
    context_data = build_expression_context(context)

    try do
      case ExpressionEngine.process_map(input_map, context_data) do
        {:ok, processed_map} ->
          {:ok, processed_map}

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
  Invoke action using MFA pattern and handle different return formats.
  """
  @spec invoke_action(Prana.Action.t(), map()) :: {:ok, term(), String.t()} | {:error, term()}
  def invoke_action(%Prana.Action{} = action, input) do
    result = apply(action.module, action.function, [input])
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
  All actions must return tuple structures - no direct values allowed.
  """
  @spec process_action_result(term(), Prana.Action.t()) :: {:ok, term(), String.t()} | {:error, term()}
  def process_action_result(result, %Prana.Action{} = action) do
    case result do
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
           "message" => "Actions must return {:ok, data} | {:error, error} | {:ok, data, port} | {:error, error, port}"
         }}
    end
  end

  @doc """
  Update execution context with node results.
  """
  @spec update_context(ExecutionContext.t(), Node.t(), term()) ::
          {:ok, ExecutionContext.t()} | {:error, term()}
  def update_context(%ExecutionContext{} = context, %Node{} = node, output_data) do
    # Store result only under node.custom_id for flexible access
    nodes = Map.put(context.nodes, node.custom_id, output_data)
    updated_context = %{context | nodes: nodes}
    {:ok, updated_context}
  end

  # Private helper functions

  @spec build_expression_context(ExecutionContext.t()) :: map()
  defp build_expression_context(%ExecutionContext{} = context) do
    %{
      "input" => context.input,
      "nodes" => context.nodes,
      "variables" => context.variables
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
end
