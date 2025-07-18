defmodule Prana.Workflow do
  @moduledoc """
  Represents a complete workflow with nodes and connections

  """
  use Skema

  defschema do
    field(:id, :string, required: true)
    field(:name, :string, required: true)
    field(:description, :string, default: nil)
    field(:version, :integer, default: 1)
    field(:nodes, {:array, Prana.Node}, default: [])

    # connections: %{String.t() => %{String.t() => [Prana.Connection.t()]}},
    field(:connections, :map, default: %{})
    field(:variables, :map, default: %{})
  end

  @doc """
  Creates a new workflow
  """
  def new(name, description) do
    new(%{
      id: generate_id(),
      name: name,
      description: description,
      nodes: [],
      connections: %{},
      variables: %{}
    })
  end

  @doc """
  Loads a workflow from a map
  """
  def from_map(data) when is_map(data) do
    {:ok, data} = Skema.load(data, __MODULE__)
    data
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

  defp generate_id do
    UUID.uuid4()
  end
end
