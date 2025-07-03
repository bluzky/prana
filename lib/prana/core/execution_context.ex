defmodule Prana.ExecutionContext do
  @moduledoc """
  Represents the shared execution context for a workflow
  """

  @type t :: %__MODULE__{
          execution_id: String.t(),
          workflow: Prana.Workflow.t(),
          execution: Prana.Execution.t(),
          # node_id => output_data
          nodes: map(),
          # workflow variables
          variables: map(),
          # initial input data
          input: map(),
          pending_nodes: MapSet.t(),
          completed_nodes: MapSet.t(),
          failed_nodes: MapSet.t(),
          # Track execution order for conditional branching
          executed_nodes: [String.t()],
          # Track active conditional paths: {from_node_id, from_port} => true
          active_paths: map(),
          metadata: map()
        }

  defstruct [
    :execution_id,
    :workflow,
    :execution,
    :nodes,
    :variables,
    :input,
    :pending_nodes,
    :completed_nodes,
    :failed_nodes,
    executed_nodes: [],
    active_paths: %{},
    metadata: %{}
  ]

  @doc """
  Creates a new execution context
  """
  def new(workflow, execution, additional_context \\ %{}) do
    Map.merge(
      %__MODULE__{
        execution_id: execution.id,
        workflow: workflow,
        execution: execution,
        nodes: %{},
        variables: workflow.variables,
        input: execution.input_data,
        pending_nodes: MapSet.new(),
        completed_nodes: MapSet.new(),
        failed_nodes: MapSet.new(),
        executed_nodes: [],
        active_paths: %{},
        metadata: %{}
      },
      additional_context
    )
  end

  @doc """
  Adds node output to context
  """
  def add_node_output(%__MODULE__{} = context, node_id, output_data) do
    %{
      context
      | nodes: Map.put(context.nodes, node_id, output_data),
        completed_nodes: MapSet.put(context.completed_nodes, node_id)
    }
  end

  @doc """
  Marks node as failed
  """
  def mark_node_failed(%__MODULE__{} = context, node_id) do
    %{context | failed_nodes: MapSet.put(context.failed_nodes, node_id)}
  end

  @doc """
  Marks node as pending
  """
  def mark_node_pending(%__MODULE__{} = context, node_id) do
    %{context | pending_nodes: MapSet.put(context.pending_nodes, node_id)}
  end

  @doc """
  Updates workflow variables
  """
  def update_variables(%__MODULE__{} = context, new_variables) do
    %{context | variables: Map.merge(context.variables, new_variables)}
  end


  @doc """
  Gets expression evaluation context
  """
  def to_expression_context(%__MODULE__{} = context) do
    %{
      nodes: context.nodes,
      variables: context.variables,
      input: context.input,
      executed_nodes: context.executed_nodes,
      execution: Map.take(context, [:execution_id, :execution])
    }
  end

  @doc """
  Adds node to execution path tracking
  """
  def add_executed_node(%__MODULE__{} = context, node_id) do
    %{context | executed_nodes: [node_id | context.executed_nodes]}
  end

  @doc """
  Marks a conditional path as active
  """
  def mark_path_active(%__MODULE__{} = context, from_node_id, from_port) do
    path_key = {from_node_id, from_port}
    %{context | active_paths: Map.put(context.active_paths, path_key, true)}
  end

  @doc """
  Checks if a conditional path is active
  """
  def path_active?(%__MODULE__{} = context, from_node_id, from_port) do
    path_key = {from_node_id, from_port}
    Map.get(context.active_paths, path_key, false)
  end

  @doc """
  Checks if node is on an active execution path for conditional branching
  """
  def node_on_active_path?(%__MODULE__{} = context, node_id) do
    # Find all incoming connections to this node
    incoming_connections = get_incoming_connections(context.workflow, node_id)
    
    if Enum.empty?(incoming_connections) do
      # Entry/trigger nodes are always on active path
      true
    else
      # Node is on active path if ANY incoming connection is from an active path
      Enum.any?(incoming_connections, fn conn ->
        path_active?(context, conn.from, conn.from_port)
      end)
    end
  end

  # Helper function to get incoming connections for a node
  defp get_incoming_connections(workflow, node_id) do
    Enum.filter(workflow.connections, fn conn ->
      conn.to == node_id
    end)
  end
end
