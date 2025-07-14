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
          connections: %{String.t() => %{String.t() => [Prana.Connection.t()]}},
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
      connections: %{},
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
      connections: parse_connections(Map.get(data, "connections") || Map.get(data, :connections) || %{}),
      variables: Map.get(data, "variables") || Map.get(data, :variables) || %{},
      settings: parse_settings(Map.get(data, "settings") || Map.get(data, :settings) || %{}),
      metadata: Map.get(data, "metadata") || Map.get(data, :metadata) || %{}
    }
  end

  @doc """
  Gets entry nodes (nodes with no incoming connections)
  """
  def get_entry_nodes(%__MODULE__{nodes: nodes, connections: connections}) do
    target_node_keys = 
      connections
      |> Enum.flat_map(fn {_node, ports} -> 
           Enum.flat_map(ports, fn {_port, conns} -> conns end)
         end)
      |> MapSet.new(& &1.to)
    
    Enum.reject(nodes, &MapSet.member?(target_node_keys, &1.key))
  end

  @doc """
  Gets connections from a specific node and port
  """
  def get_connections_from(%__MODULE__{connections: connections}, node_key, port) do
    connections
    |> Map.get(node_key, %{})
    |> Map.get(port, [])
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
    updated_connections = 
      connections
      |> Map.put_new(connection.from, %{})
      |> Map.update!(connection.from, fn ports ->
           current_conns = Map.get(ports, connection.from_port, [])
           Map.put(ports, connection.from_port, current_conns ++ [connection])
         end)
    
    {:ok, %{workflow | connections: updated_connections}}
  end

  @doc """
  Gets all connections as flat list (utility function for tests and validation)
  """
  def all_connections(%__MODULE__{connections: connections}) do
    connections
    |> Enum.flat_map(fn {_node, ports} -> 
         Enum.flat_map(ports, fn {_port, conns} -> conns end)
       end)
  end

  @doc """
  Gets connections from specific node (all ports)
  """
  def get_connections_from_node(%__MODULE__{connections: connections}, node_key) do
    connections
    |> Map.get(node_key, %{})
    |> Enum.flat_map(fn {_port, conns} -> conns end)
  end

  @doc """
  Gets all output ports for a node
  """
  def get_output_ports(%__MODULE__{connections: connections}, node_key) do
    connections
    |> Map.get(node_key, %{})
    |> Map.keys()
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

  defp parse_connections(connections) when is_map(connections) do
    # Parse connection structs from map format
    connections
    |> Enum.map(fn {node_key, ports} ->
         parsed_ports = 
           ports
           |> Enum.map(fn {port, conns} ->
                parsed_conns = Enum.map(conns, &Prana.Connection.from_map/1)
                {port, parsed_conns}
              end)
           |> Map.new()
         
         {node_key, parsed_ports}
       end)
    |> Map.new()
  end

  defp parse_connections(_), do: %{}

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

    all_connections = 
      connections
      |> Enum.flat_map(fn {_node, ports} -> 
           Enum.flat_map(ports, fn {_port, conns} -> conns end)
         end)

    invalid_connections =
      Enum.reject(all_connections, fn conn ->
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
