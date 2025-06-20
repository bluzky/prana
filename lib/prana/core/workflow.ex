defmodule Prana.Workflow do
  @moduledoc """
  Represents a complete workflow with nodes and connections
  """
  
  @type status :: :draft | :active | :paused | :archived
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    description: String.t() | nil,
    version: integer(),
    status: status(),
    tags: [String.t()],
    nodes: [Prana.Node.t()],
    connections: [Prana.Connection.t()],
    variables: map(),
    settings: Prana.WorkflowSettings.t(),
    metadata: map(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    created_by: String.t() | nil,
    organization_id: String.t() | nil
  }

  defstruct [
    :id, :name, :description, :version, :status, :tags,
    :nodes, :connections, :variables, :settings, :metadata,
    :created_at, :updated_at, :created_by, :organization_id
  ]

  @doc """
  Creates a new workflow
  """
  def new(name, description \\ nil) do
    %__MODULE__{
      id: generate_id(),
      name: name,
      description: description,
      version: 1,
      status: :draft,
      tags: [],
      nodes: [],
      connections: [],
      variables: %{},
      settings: %Prana.WorkflowSettings{},
      metadata: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      created_by: nil,
      organization_id: nil
    }
  end

  @doc """
  Adds a node to the workflow
  """
  def add_node(%__MODULE__{} = workflow, %Prana.Node{} = node) do
    %{workflow | 
      nodes: workflow.nodes ++ [node],
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Adds a connection to the workflow
  """
  def add_connection(%__MODULE__{} = workflow, %Prana.Connection{} = connection) do
    %{workflow | 
      connections: workflow.connections ++ [connection],
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Gets entry nodes (nodes with no incoming connections)
  """
  def get_entry_nodes(%__MODULE__{nodes: nodes, connections: connections}) do
    target_node_ids = MapSet.new(connections, & &1.to_node_id)
    Enum.reject(nodes, &MapSet.member?(target_node_ids, &1.id))
  end

  @doc """
  Gets connections from a specific node and port
  """
  def get_connections_from(%__MODULE__{connections: connections}, node_id, port) do
    Enum.filter(connections, &(&1.from_node_id == node_id && &1.from_port == port))
  end

  @doc """
  Gets a node by ID
  """
  def get_node_by_id(%__MODULE__{nodes: nodes}, node_id) do
    Enum.find(nodes, &(&1.id == node_id))
  end

  @doc """
  Validates workflow structure
  """
  def valid?(%__MODULE__{} = workflow) do
    with :ok <- validate_nodes(workflow.nodes),
         :ok <- validate_connections(workflow.connections, workflow.nodes),
         :ok <- validate_no_cycles(workflow) do
      :ok
    else
      {:error, _reason} = error -> error
    end
  end

  # Private functions
  
  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64() |> binary_part(0, 16)
  end

  defp validate_nodes(nodes) do
    if Enum.all?(nodes, &Prana.Node.valid?/1) do
      :ok
    else
      {:error, "Invalid nodes found"}
    end
  end

  defp validate_connections(connections, nodes) do
    node_ids = MapSet.new(nodes, & &1.id)
    
    invalid_connections = 
      Enum.reject(connections, fn conn ->
        MapSet.member?(node_ids, conn.from_node_id) && 
        MapSet.member?(node_ids, conn.to_node_id)
      end)

    if Enum.empty?(invalid_connections) do
      :ok
    else
      {:error, "Connections reference non-existent nodes"}
    end
  end

  defp validate_no_cycles(%__MODULE__{} = workflow) do
    # Simple cycle detection using DFS
    # In a production system, you'd want more sophisticated cycle detection
    case detect_cycles(workflow) do
      [] -> :ok
      _cycles -> {:error, "Workflow contains cycles"}
    end
  end

  defp detect_cycles(_workflow) do
    # Simplified cycle detection - in real implementation would use proper graph algorithms
    []
  end
end
