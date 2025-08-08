defmodule Prana.Node do
  @moduledoc """
  Represents an individual node in a workflow
  """
  use Skema

  defschema do
    field(:name, :string)
    field(:key, :string, required: true)
    field(:type, :string, required: true)
    field(:params, :map, default: %{})
    field(:metadata, :map, default: %{})
  end

  @doc """
  Creates a new node with type format "<integration>.<action>"
  """
  def new(name, type, params \\ %{}, key \\ nil) do
    new(%{
      # id: generate_id(),
      key: key || generate_custom_id(name),
      name: name,
      type: type,
      params: params
    })
  end

  @doc """
  Loads a node from a map with string keys, converting to proper types.

  Automatically converts:
  - String keys to atoms where appropriate
  - Preserves complex nested params structures

  ## Examples

      node_map = %{
        "key" => "api_call",
        "name" => "API Call",
        "type" => "http.request",
        "params" => %{
          "method" => "GET",
          "url" => "https://api.example.com/users",
          "headers" => %{"Authorization" => "Bearer token"}
        }
      }
      
      node = Node.from_map(node_map)
      # Complex params are preserved as-is
  """
  def from_map(data) when is_map(data) do
    {:ok, data} = Skema.load(data, __MODULE__)
    data
  end

  @doc """
  Converts a node to a JSON-compatible map.

  Preserves all node data including complex nested params for round-trip serialization.

  ## Examples

      node = %Node{
        key: "api_call",
        name: "API Call",
        type: "http.request",
        params: %{"method" => "GET", "url" => "https://api.example.com"}
      }
      
      node_map = Node.to_map(node)
      json_string = Jason.encode!(node_map)
      # Ready for storage or API transport
  """
  def to_map(%__MODULE__{} = node) do
    Map.from_struct(node)
  end

  defp generate_custom_id(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end
end
