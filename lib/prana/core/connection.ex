defmodule Prana.Connection do
  @moduledoc """
  Represents a connection between two nodes
  """

  use Skema

  defschema do
    field(:from, :string, required: true)
    field(:from_port, :string, default: "main")
    field(:to, :string, required: true)
    field(:to_port, :string, default: "main")
  end

  @doc """
  Creates a new connection
  """
  def new(from, from_port, to, to_port \\ "main") do
    new(%{
      from: from,
      from_port: from_port,
      to: to,
      to_port: to_port
    })
  end

  @doc """
  Loads a connection from a map with string keys, converting to proper types.

  Automatically converts:
  - String keys to atoms where appropriate
  - Applies default port values ("main") when not specified

  ## Examples

      connection_map = %{
        "from" => "node_1",
        "from_port" => "success",
        "to" => "node_2",
        "to_port" => "input"
      }
      
      connection = Connection.from_map(connection_map)
      # Port routing is preserved with proper defaults
  """
  def from_map(data) when is_map(data) do
    {:ok, data} = Skema.load(data, __MODULE__)
    data
  end

  @doc """
  Converts a connection to a JSON-compatible map.

  Preserves all connection routing data for round-trip serialization.

  ## Examples

      connection = %Connection{
        from: "node_1",
        from_port: "success",
        to: "node_2",
        to_port: "input"
      }
      
      connection_map = Connection.to_map(connection)
      json_string = Jason.encode!(connection_map)
      # Ready for storage or API transport
  """
  def to_map(%__MODULE__{} = connection) do
    Map.from_struct(connection)
  end
end
