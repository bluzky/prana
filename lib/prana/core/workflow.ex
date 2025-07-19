defmodule Prana.Workflow do
  @moduledoc """
  Represents a complete workflow with nodes and connections

  """
  use Skema

  defschema do
    field(:id, :string, required: true)
    field(:name, :string, required: true)
    field(:version, :integer, default: 1)
    field(:nodes, {:array, Prana.Node}, default: [])

    # connections: %{String.t() => %{String.t() => [Prana.Connection.t()]}},
    field(:connections, :map, default: %{})
    field(:variables, :map, default: %{})
  end

  @doc """
  Loads a workflow from a map with string keys, converting nested structures to proper types.

  Automatically converts:
  - Nested connection maps to Connection structs
  - Node maps to Node structs (via Skema)
  - String keys to atoms where appropriate

  ## Examples

      workflow_map = %{
        "id" => "wf_123",
        "name" => "User Registration",
        "nodes" => [%{"key" => "validate", "type" => "manual.validate"}],
        "connections" => %{
          "validate" => %{
            "success" => [%{"from" => "validate", "to" => "create_user"}]
          }
        }
      }

      workflow = Workflow.from_map(workflow_map)
      # All nested structures are properly converted to structs
  """
  def from_map(data) when is_map(data) do
    {:ok, workflow} = Skema.load(data, __MODULE__)

    # Convert nested connection maps to Connection structs
    connections = convert_connections_to_structs(workflow.connections)

    %{workflow | connections: connections}
  end

  @doc """
  Converts a workflow to a JSON-compatible map with nested structs converted to maps.

  Automatically converts:
  - Connection structs to maps
  - Node structs to maps
  - Preserves all data for round-trip serialization

  ## Examples

      workflow = %Workflow{
        id: "wf_123",
        name: "User Registration",
        nodes: [%Node{key: "validate", type: "manual.validate"}],
        connections: %{
          "validate" => %{
            "success" => [%Connection{from: "validate", to: "create_user"}]
          }
        }
      }

      workflow_map = Workflow.to_map(workflow)
      json_string = Jason.encode!(workflow_map)
      # Ready for storage or API transport
  """
  def to_map(%__MODULE__{} = workflow) do
    workflow
    |> Map.from_struct()
    |> Map.update!(:nodes, fn nodes ->
      Enum.map(nodes, &Map.from_struct/1)
    end)
    |> Map.update!(:connections, fn connections ->
      convert_connections_to_maps(connections)
    end)
  end

  # Convert nested connection maps to Connection structs
  defp convert_connections_to_structs(connections) when is_map(connections) do
    Map.new(connections, fn {node_key, ports} ->
      converted_ports =
        Map.new(ports, fn {port_name, conns} ->
          converted_conns =
            Enum.map(conns, fn conn_map ->
              Prana.Connection.from_map(conn_map)
            end)

          {port_name, converted_conns}
        end)

      {node_key, converted_ports}
    end)
  end

  # Convert nested Connection structs to maps
  defp convert_connections_to_maps(connections) when is_map(connections) do
    Map.new(connections, fn {node_key, ports} ->
      converted_ports =
        Map.new(ports, fn {port_name, conns} ->
          converted_conns =
            Enum.map(conns, fn conn_struct ->
              Map.from_struct(conn_struct)
            end)

          {port_name, converted_conns}
        end)

      {node_key, converted_ports}
    end)
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
end
