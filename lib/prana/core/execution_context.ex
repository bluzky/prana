defmodule Prana.ExecutionContext do
  @moduledoc """
  Represents the shared execution context for a workflow
  """
  
  @type t :: %__MODULE__{
    execution_id: String.t(),
    workflow: Prana.Workflow.t(),
    execution: Prana.Execution.t(),
    nodes: map(),           # node_id => output_data
    variables: map(),       # workflow variables
    input: map(),           # initial input data
    pending_nodes: MapSet.t(),
    completed_nodes: MapSet.t(),
    failed_nodes: MapSet.t(),
    metadata: map()
  }

  defstruct [
    :execution_id, :workflow, :execution, :nodes, :variables, :input,
    :pending_nodes, :completed_nodes, :failed_nodes, metadata: %{}
  ]

  @doc """
  Creates a new execution context
  """
  def new(workflow, execution, additional_context \\ %{}) do
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
      metadata: %{}
    }
    |> Map.merge(additional_context)
  end

  @doc """
  Adds node output to context
  """
  def add_node_output(%__MODULE__{} = context, node_id, output_data) do
    %{context |
      nodes: Map.put(context.nodes, node_id, output_data),
      completed_nodes: MapSet.put(context.completed_nodes, node_id)
    }
  end

  @doc """
  Marks node as failed
  """
  def mark_node_failed(%__MODULE__{} = context, node_id) do
    %{context |
      failed_nodes: MapSet.put(context.failed_nodes, node_id)
    }
  end

  @doc """
  Marks node as pending
  """
  def mark_node_pending(%__MODULE__{} = context, node_id) do
    %{context |
      pending_nodes: MapSet.put(context.pending_nodes, node_id)
    }
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
      execution: Map.take(context, [:execution_id, :execution])
    }
  end
end
