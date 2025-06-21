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
          metadata: map()
        }

  defstruct [
    :id,
    :from_node_id,
    :from_port,
    :to_node_id,
    :to_port,
    conditions: [],
    data_mapping: %{},
    metadata: %{}
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
      metadata: %{}
    }
  end

  @doc """
  Loads a connection from a map
  """
  def from_map(data) when is_map(data) do
    %__MODULE__{
      id: Map.get(data, "id") || Map.get(data, :id) || generate_id(),
      from_node_id: Map.get(data, "from_node_id") || Map.get(data, :from_node_id),
      from_port: Map.get(data, "from_port") || Map.get(data, :from_port),
      to_node_id: Map.get(data, "to_node_id") || Map.get(data, :to_node_id),
      to_port: Map.get(data, "to_port") || Map.get(data, :to_port) || "input",
      conditions: parse_conditions(Map.get(data, "conditions") || Map.get(data, :conditions) || []),
      data_mapping: Map.get(data, "data_mapping") || Map.get(data, :data_mapping) || %{},
      metadata: Map.get(data, "metadata") || Map.get(data, :metadata) || %{}
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
    16 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 16)
  end

  defp parse_conditions(conditions) when is_list(conditions) do
    Enum.map(conditions, &parse_condition/1)
  end

  defp parse_condition(condition) when is_map(condition) do
    struct(Prana.Condition, condition)
  end
end
