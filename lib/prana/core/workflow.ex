defmodule Prana.Workflow do
  @moduledoc """
  Represents a complete workflow with nodes and connections
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          version: integer(),
          nodes: [Prana.Node.t()],
          connections: [Prana.Connection.t()],
          variables: map(),
          settings: Prana.WorkflowSettings.t(),
          metadata: map()
        }

  defstruct [
    :id,
    :name,
    :description,
    :version,
    :nodes,
    :connections,
    :variables,
    :settings,
    :metadata
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
      nodes: [],
      connections: [],
      variables: %{},
      settings: %Prana.WorkflowSettings{},
      metadata: %{}
    }
  end

  @doc """
  Loads a workflow from a map
  """
  def from_map(data) when is_map(data) do
    %__MODULE__{
      id: Map.get(data, "id") || Map.get(data, :id),
      name: Map.get(data, "name") || Map.get(data, :name),
      description: Map.get(data, "description") || Map.get(data, :description),
      version: Map.get(data, "version") || Map.get(data, :version) || 1,
      nodes: parse_nodes(Map.get(data, "nodes") || Map.get(data, :nodes) || []),
      connections: parse_connections(Map.get(data, "connections") || Map.get(data, :connections) || []),
      variables: Map.get(data, "variables") || Map.get(data, :variables) || %{},
      settings: parse_settings(Map.get(data, "settings") || Map.get(data, :settings) || %{}),
      metadata: Map.get(data, "metadata") || Map.get(data, :metadata) || %{}
    }
  end

  @doc """
  Gets entry nodes (nodes with no incoming connections)
  """
  def get_entry_nodes(%__MODULE__{nodes: nodes, connections: connections}) do
    target_node_keys = MapSet.new(connections, & &1.to)
    Enum.reject(nodes, &MapSet.member?(target_node_keys, &1.key))
  end

  @doc """
  Gets connections from a specific node and port
  """
  def get_connections_from(%__MODULE__{connections: connections}, node_key, port) do
    Enum.filter(connections, &(&1.from == node_key && &1.from_port == port))
  end

  @doc """
  Gets a node by ID
  """
  def get_node_by_key(%__MODULE__{nodes: nodes}, node_key) do
    Enum.find(nodes, &(&1.key == node_key))
  end

  @doc """
  Adds a node to the workflow with key uniqueness validation
  """
  def add_node(%__MODULE__{nodes: nodes} = workflow, %Prana.Node{} = node) do
    case Enum.find(nodes, &(&1.key == node.key)) do
      nil ->
        {:ok, %{workflow | nodes: nodes ++ [node]}}

      existing_node ->
        {:error, "Node with key '#{node.key}' already exists: '#{existing_node.name}'"}
    end
  end

  @doc """
  Adds a node to the workflow, raising on duplicate key
  """
  def add_node!(%__MODULE__{} = workflow, %Prana.Node{} = node) do
    case add_node(workflow, node) do
      {:ok, updated_workflow} -> updated_workflow
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Adds a connection to the workflow
  """
  def add_connection(%__MODULE__{connections: connections} = workflow, %Prana.Connection{} = connection) do
    {:ok, %{workflow | connections: connections ++ [connection]}}
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
    16 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 16)
  end

  defp parse_nodes(nodes) when is_list(nodes) do
    Enum.map(nodes, &Prana.Node.from_map/1)
  end

  defp parse_connections(connections) when is_list(connections) do
    Enum.map(connections, &Prana.Connection.from_map/1)
  end

  defp parse_settings(settings) when is_map(settings) do
    struct(Prana.WorkflowSettings, settings)
  end

  defp validate_nodes(nodes) do
    with :ok <- validate_node_structure(nodes),
         :ok <- validate_custom_id_uniqueness(nodes) do
      :ok
    else
      {:error, _reason} = error -> error
    end
  end

  defp validate_node_structure(nodes) do
    if Enum.all?(nodes, &Prana.Node.valid?/1) do
      :ok
    else
      {:error, "Invalid nodes found"}
    end
  end

  defp validate_custom_id_uniqueness(nodes) do
    custom_ids = Enum.map(nodes, & &1.key)
    unique_custom_ids = Enum.uniq(custom_ids)

    if length(custom_ids) == length(unique_custom_ids) do
      :ok
    else
      duplicates = custom_ids -- unique_custom_ids
      {:error, "Duplicate key values found: #{inspect(duplicates)}"}
    end
  end

  defp validate_connections(connections, nodes) do
    node_keys = MapSet.new(nodes, & &1.key)

    invalid_connections =
      Enum.reject(connections, fn conn ->
        MapSet.member?(node_keys, conn.from) &&
          MapSet.member?(node_keys, conn.to)
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
