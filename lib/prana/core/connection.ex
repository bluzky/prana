defmodule Prana.Connection do
  @moduledoc """
  Represents a connection between two nodes
  """
  
  @type t :: %__MODULE__{
    id: String.t(),
    from_node_id: String.t(),
    from_port: String.t(),
    to_node_id: String.t(),
    to_port: String.t(),
    conditions: [Prana.Condition.t()],
    data_mapping: map(),
    enabled: boolean(),
    metadata: map()
  }

  defstruct [
    :id, :from_node_id, :from_port, :to_node_id, :to_port,
    conditions: [], data_mapping: %{}, enabled: true, metadata: %{}
  ]

  @doc """
  Creates a new connection
  """
  def new(from_node_id, from_port, to_node_id, to_port \\ "input") do
    %__MODULE__{
      id: generate_id(),
      from_node_id: from_node_id,
      from_port: from_port,
      to_node_id: to_node_id,
      to_port: to_port,
      conditions: [],
      data_mapping: %{},
      enabled: true,
      metadata: %{}
    }
  end

  @doc """
  Validates a connection
  """
  def valid?(%__MODULE__{} = connection) do
    required_fields = [:id, :from_node_id, :from_port, :to_node_id, :to_port]
    
    missing_fields = 
      Enum.reject(required_fields, fn field ->
        value = Map.get(connection, field)
        value && value != ""
      end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required connection fields: #{inspect(missing_fields)}"}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64() |> binary_part(0, 16)
  end
end
