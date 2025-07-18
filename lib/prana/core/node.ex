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
  Loads a node from a map
  """
  def from_map(data) when is_map(data) do
    {:ok, data} = Skema.load(data, __MODULE__)
    data
  end

  defp generate_custom_id(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end
end
