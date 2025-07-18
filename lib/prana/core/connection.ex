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
  Loads a connection from a map
  """
  def from_map(data) when is_map(data) do
    {:ok, data} = Skema.load(data, __MODULE__)
    data
  end
end
